const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Crowdfunding (ERC20)", function () {
  let crowdfunding;
  let token;
  let owner;
  let alice;
  let bob;

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    const Crowdfunding = await ethers.getContractFactory("Crowdfunding");
    crowdfunding = await Crowdfunding.deploy();
    await crowdfunding.waitForDeployment();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token = await MockERC20.deploy("MockToken", "MOCK", ethers.parseUnits("1000000", 18));
    await token.waitForDeployment();

    await token.mint(alice.address, ethers.parseUnits("1000", 18));
    await token.mint(bob.address, ethers.parseUnits("1000", 18));
  });

  async function createTokenCampaign(goalTokens) {
    const block = await ethers.provider.getBlock("latest");
    const deadline = block.timestamp + 3600;
    const tx = await crowdfunding.createCampaign(
      ethers.parseUnits(goalTokens, 18),
      deadline,
      token.target
    );
    await tx.wait();
    const id = await crowdfunding.campaignCount();
    return { id, deadline };
  }

  it("accepts ERC20 contributions and tracks balances", async function () {
    const { id } = await createTokenCampaign("500");

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await token.connect(bob).approve(crowdfunding.target, ethers.parseUnits("50", 18));

    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));
    await crowdfunding.connect(bob).contributeToken(id, ethers.parseUnits("50", 18));

    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.raised).to.equal(ethers.parseUnits("150", 18));
    expect(await crowdfunding.contributions(id, alice.address)).to.equal(ethers.parseUnits("100", 18));
    expect(await crowdfunding.contributions(id, bob.address)).to.equal(ethers.parseUnits("50", 18));
  });

  it("rejects ETH contributions for token campaigns", async function () {
    const { id } = await createTokenCampaign("100");

    await expect(
      crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(crowdfunding, "WrongCurrency");
  });

  it("allows creator withdrawal after goal reached", async function () {
    const { id } = await createTokenCampaign("100");

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

    await crowdfunding.withdraw(id);

    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.withdrawn).to.equal(true);
    expect(await token.balanceOf(owner.address)).to.equal(ethers.parseUnits("1000100", 18));
  });

  it("processes refunds when goal not reached", async function () {
    const { id } = await createTokenCampaign("500");

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.connect(alice).refund(id);
    expect(await crowdfunding.contributions(id, alice.address)).to.equal(0n);
  });

  it("rejects refunds before deadline or after success", async function () {
    const { id } = await createTokenCampaign("100");

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

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
