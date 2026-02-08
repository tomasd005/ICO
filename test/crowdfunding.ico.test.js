const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Crowdfunding (ICO)", function () {
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
    token = await MockERC20.deploy("SaleToken", "SALE", ethers.parseUnits("1000000", 18));
    await token.waitForDeployment();

    await token.mint(owner.address, ethers.parseUnits("10000", 18));
  });

  async function createIcoCampaign({ goalEth = "1", pricePerEth = "1000" } = {}) {
    const block = await ethers.provider.getBlock("latest");
    const deadline = block.timestamp + 3600;
    const tx = await crowdfunding.createIcoCampaign(
      ethers.parseEther(goalEth),
      deadline,
      token.target,
      0,
      false,
      false,
      ethers.parseUnits(pricePerEth, 18)
    );
    await tx.wait();
    const id = await crowdfunding.campaignCount();
    return { id, deadline };
  }

  async function depositIcoTokens(campaignId, amount) {
    await token.approve(crowdfunding.target, amount);
    await crowdfunding.depositIcoTokens(campaignId, amount);
  }

  it("accepts ICO contributions and allows token claims", async function () {
    const { id } = await createIcoCampaign({ goalEth: "1", pricePerEth: "1000" });
    const pool = ethers.parseUnits("2000", 18);
    await depositIcoTokens(id, pool);

    await crowdfunding.connect(alice).contributeICO(id, { value: ethers.parseEther("0.5") });
    await crowdfunding.connect(bob).contributeICO(id, { value: ethers.parseEther("0.5") });

    expect(await crowdfunding.icoOwed(id, alice.address)).to.equal(ethers.parseUnits("500", 18));
    expect(await crowdfunding.icoOwed(id, bob.address)).to.equal(ethers.parseUnits("500", 18));

    await crowdfunding.connect(alice).claimIcoTokens(id);
    await crowdfunding.connect(bob).claimIcoTokens(id);

    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseUnits("500", 18));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseUnits("500", 18));
  });

  it("prevents ICO contributions without enough token pool", async function () {
    const { id } = await createIcoCampaign({ goalEth: "1", pricePerEth: "1000" });

    await expect(
      crowdfunding.connect(alice).contributeICO(id, { value: ethers.parseEther("0.5") })
    ).to.be.revertedWithCustomError(crowdfunding, "InsufficientIcoTokens");
  });

  it("refunds ETH and releases ICO allocation when goal not reached", async function () {
    const { id } = await createIcoCampaign({ goalEth: "2", pricePerEth: "1000" });
    const pool = ethers.parseUnits("2000", 18);
    await depositIcoTokens(id, pool);

    await crowdfunding.connect(alice).contributeICO(id, { value: ethers.parseEther("1") });

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.connect(alice).refund(id);

    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.tokensSold).to.equal(0n);
    expect(await crowdfunding.icoOwed(id, alice.address)).to.equal(0n);
  });

  it("allows creator to withdraw unsold ICO tokens after deadline", async function () {
    const { id } = await createIcoCampaign({ goalEth: "2", pricePerEth: "1000" });
    const pool = ethers.parseUnits("1000", 18);
    await depositIcoTokens(id, pool);

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.withdrawIcoTokens(id);
    expect(await token.balanceOf(owner.address)).to.equal(ethers.parseUnits("1010000", 18));
  });
});
