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

  async function createTokenCampaign({
    goalTokens = "500",
    minTokens = "0",
    whitelistEnabled = false,
    rewardEnabled = false,
  } = {}) {
    const block = await ethers.provider.getBlock("latest");
    const deadline = block.timestamp + 3600;
    const tx = await crowdfunding.createCampaign(
      ethers.parseUnits(goalTokens, 18),
      deadline,
      token.target,
      ethers.parseUnits(minTokens, 18),
      whitelistEnabled,
      rewardEnabled
    );
    await tx.wait();
    const id = await crowdfunding.campaignCount();
    return { id, deadline };
  }

  it("accepts ERC20 contributions and tracks balances", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "500" });

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
    const { id } = await createTokenCampaign({ goalTokens: "100" });

    await expect(
      crowdfunding.connect(alice).contributeETH(id, { value: ethers.parseEther("1") })
    ).to.be.revertedWithCustomError(crowdfunding, "WrongCurrency");
  });

  it("allows creator withdrawal after goal reached", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "100" });

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

    await crowdfunding.withdraw(id);

    const campaign = await crowdfunding.campaigns(id);
    expect(campaign.withdrawn).to.equal(true);
    expect(await token.balanceOf(owner.address)).to.equal(ethers.parseUnits("1000100", 18));
  });

  it("processes refunds when goal not reached", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "500" });

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.connect(alice).refund(id);
    expect(await crowdfunding.contributions(id, alice.address)).to.equal(0n);
  });

  it("refunds multiple ERC20 contributors individually", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "500" });

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await token.connect(bob).approve(crowdfunding.target, ethers.parseUnits("50", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));
    await crowdfunding.connect(bob).contributeToken(id, ethers.parseUnits("50", 18));

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await crowdfunding.connect(alice).refund(id);
    expect(await crowdfunding.contributions(id, alice.address)).to.equal(0n);
    expect(await crowdfunding.contributions(id, bob.address)).to.equal(ethers.parseUnits("50", 18));

    await crowdfunding.connect(bob).refund(id);
    expect(await crowdfunding.contributions(id, bob.address)).to.equal(0n);
    expect(await token.balanceOf(alice.address)).to.equal(ethers.parseUnits("1000", 18));
    expect(await token.balanceOf(bob.address)).to.equal(ethers.parseUnits("1000", 18));
    expect(await token.balanceOf(crowdfunding.target)).to.equal(0n);
  });

  it("rejects refunds before deadline or after success", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "100" });

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

  it("enforces minimum contribution for tokens", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "200", minTokens: "10" });

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("5", 18));
    await expect(
      crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("5", 18))
    ).to.be.revertedWithCustomError(crowdfunding, "BelowMinimumContribution");

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("10", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("10", 18));
  });

  it("enforces whitelist when enabled", async function () {
    const { id } = await createTokenCampaign({ goalTokens: "200", whitelistEnabled: true });

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("10", 18));
    await expect(
      crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("10", 18))
    ).to.be.revertedWithCustomError(crowdfunding, "NotWhitelisted");

    await crowdfunding.setWhitelist(id, alice.address, true);
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("10", 18));
  });

  it("takes a platform fee on token withdrawal when configured", async function () {
    await crowdfunding.setFee(200, bob.address);
    const { id } = await createTokenCampaign({ goalTokens: "100" });
    const bobBefore = await token.balanceOf(bob.address);

    await token.connect(alice).approve(crowdfunding.target, ethers.parseUnits("100", 18));
    await crowdfunding.connect(alice).contributeToken(id, ethers.parseUnits("100", 18));

    await crowdfunding.withdraw(id);
    const fee = (ethers.parseUnits("100", 18) * 200n) / 10000n;
    const bobAfter = await token.balanceOf(bob.address);
    expect(bobAfter - bobBefore).to.equal(fee);
  });
});
