const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Crowdfunding (ETH)", function () {
  let crowdfunding;
  let owner;
  let alice;
  let bob;

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    const Crowdfunding = await ethers.getContractFactory("Crowdfunding");
    crowdfunding = await Crowdfunding.deploy();
    await crowdfunding.waitForDeployment();
  });

  async function createEthCampaign(goalEth) {
    const block = await ethers.provider.getBlock("latest");
    const deadline = block.timestamp + 3600;
    const tx = await crowdfunding.createCampaign(
      ethers.parseEther(goalEth),
      deadline,
      ethers.ZeroAddress
    );
    await tx.wait();
    const id = await crowdfunding.campaignCount();
    return { id, deadline };
  }

  it("creates a campaign with ETH currency", async function () {
    const { id, deadline } = await createEthCampaign("5");
    const campaign = await crowdfunding.campaigns(id);

    expect(campaign.creator).to.equal(owner.address);
    expect(campaign.goal).to.equal(ethers.parseEther("5"));
    expect(campaign.deadline).to.equal(BigInt(deadline));
    expect(campaign.token).to.equal(ethers.ZeroAddress);
  });

  it("accepts ETH contributions and tracks balances", async function () {
    const { id } = await createEthCampaign("3");

    await crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") });
    await crowdfunding.connect(bob).contributeETH(id, { value: ethers.parseEther("0.5") });

    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.raised).to.equal(ethers.parseEther("1.5"));
    expect(await crowdfunding.contributions(id, alice.address)).to.equal(ethers.parseEther("1"));
    expect(await crowdfunding.contributions(id, bob.address)).to.equal(ethers.parseEther("0.5"));
  });

  it("rejects zero-value ETH contributions", async function () {
    const { id } = await createEthCampaign("1");
    await expect(
      crowdfunding.connect(alice).contributeETH(id, { value: 0 })
    ).to.be.revertedWithCustomError(crowdfunding, "ZeroAmount");
  });

  it("prevents contributions after deadline", async function () {
    const { id } = await createEthCampaign("1");
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await expect(
      crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("0.1") })
    ).to.be.revertedWithCustomError(crowdfunding, "CampaignEnded");
  });

  it("allows creator withdrawal after goal reached", async function () {
    const { id } = await createEthCampaign("1");
    await crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") });

    await crowdfunding.withdraw(id);
    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.withdrawn).to.equal(true);
    expect(await ethers.provider.getBalance(crowdfunding.target)).to.equal(0n);
  });

  it("prevents non-creator withdrawal", async function () {
    const { id } = await createEthCampaign("1");
    await crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") });

    await expect(crowdfunding.connect(alice).withdraw(id)).to.be.revertedWithCustomError(
      crowdfunding,
      "NotCreator"
    );
  });

  it("processes refunds when goal not reached", async function () {
    const { id } = await createEthCampaign("5");
    await crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") });

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.connect(alice).refund(id);

    expect(await crowdfunding.contributions(id, alice.address)).to.equal(0n);
    expect(await ethers.provider.getBalance(crowdfunding.target)).to.equal(0n);
  });

  it("rejects refunds before deadline or after success", async function () {
    const { id } = await createEthCampaign("1");
    await crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") });

    await expect(crowdfunding.connect(alice).refund(id)).to.be.revertedWithCustomError(
      crowdfunding,
      "DeadlineNotReached"
    );

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await expect(crowdfunding.connect(alice).refund(id)).to.be.revertedWithCustomError(
      crowdfunding,
      "GoalReached"
    );
  });
});
