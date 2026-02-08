# Crowdfunding Smart Contract (ICO / Kickstarter-style)

[![CI](https://github.com/tomasd005/ICO/actions/workflows/test.yml/badge.svg)](https://github.com/tomasd005/ICO/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Solidity 0.8.20](https://img.shields.io/badge/Solidity-0.8.20-363636)
![Hardhat 2.x](https://img.shields.io/badge/Hardhat-2.x-F7DF1E)

Ethereum crowdfunding and ICO smart contract supporting ETH and ERC-20 fundraising with transparent goal/deadline enforcement, refunds, fees, whitelisting, DAO approvals, and reward NFTs.

## Project Overview

This project demonstrates:

- Trust-minimized campaign funding in ETH and ERC-20
- Automatic outcome handling (creator withdrawal or contributor refunds)
- Fixed-price ICO token sales with escrow and post-success token claims
- Security-focused patterns used in real Solidity systems

## Contracts

- `contracts/Crowdfunding.sol`: main campaign, ICO, fee, whitelist, DAO, and reward logic
- `contracts/MockERC20.sol`: ERC-20 token used in tests

## Feature Set

### Core (MVP)

- Create campaigns with goal, deadline, and accepted asset
- Contribute in ETH or ERC-20
- Withdraw on success
- Refund on failure

### Extended Features

- Platform fee (max 3%) with configurable fee recipient
- Campaign cancellation before first contribution
- Minimum contribution per campaign
- Whitelist-gated campaigns
- ERC-721 reward NFT minted once per contributor per campaign
- ICO campaigns with fixed token-per-ETH pricing
- DAO-controlled campaign approval gate

## Quickstart

Node requirement: LTS `20.x` (see `.nvmrc`).

### 1) Install

```bash
nvm use
npm install
```

### 2) Compile and test

```bash
npm run compile
npm test
```

### 3) Run local node and deploy

```bash
npx hardhat node
npx hardhat run scripts/deploy.js --network localhost
```

### 4) Optional quality checks

```bash
npm run lint
npm run coverage
```

## Example Flows

### ETH campaign: create -> contribute -> withdraw

```js
const [owner, alice] = await ethers.getSigners();
const Crowdfunding = await ethers.getContractFactory("Crowdfunding");
const c = await Crowdfunding.deploy();
await c.waitForDeployment();

const latest = await ethers.provider.getBlock("latest");
const deadline = latest.timestamp + 3600;

await c.createCampaign(
  ethers.parseEther("1"),
  deadline,
  ethers.ZeroAddress,
  ethers.parseEther("0.1"),
  false,
  false
);

await c.connect(alice).contributeETH(1, { value: ethers.parseEther("1") });
await c.withdraw(1);
```

### ERC-20 campaign: create -> approve -> contribute -> refund (if failed)

```js
const [owner, alice] = await ethers.getSigners();
const Token = await ethers.getContractFactory("MockERC20");
const token = await Token.deploy("Mock", "MOCK", ethers.parseUnits("1000000", 18));
await token.waitForDeployment();

await token.mint(alice.address, ethers.parseUnits("100", 18));

const latest = await ethers.provider.getBlock("latest");
const deadline = latest.timestamp + 3600;

await c.createCampaign(
  ethers.parseUnits("200", 18),
  deadline,
  token.target,
  ethers.parseUnits("10", 18),
  false,
  false
);

await token.connect(alice).approve(c.target, ethers.parseUnits("50", 18));
await c.connect(alice).contributeToken(1, ethers.parseUnits("50", 18));

await ethers.provider.send("evm_increaseTime", [3601]);
await ethers.provider.send("evm_mine", []);
await c.connect(alice).refund(1);
```

### ICO campaign: create -> deposit sale tokens -> contribute -> claim

```js
const [owner, alice] = await ethers.getSigners();
const Token = await ethers.getContractFactory("MockERC20");
const sale = await Token.deploy("Sale", "SALE", ethers.parseUnits("1000000", 18));
await sale.waitForDeployment();

const latest = await ethers.provider.getBlock("latest");
const deadline = latest.timestamp + 3600;

await c.createIcoCampaign(
  ethers.parseEther("1"),
  deadline,
  sale.target,
  0,
  false,
  false,
  ethers.parseUnits("1000", 18)
);

await sale.approve(c.target, ethers.parseUnits("1000", 18));
await c.depositIcoTokens(1, ethers.parseUnits("1000", 18));

await c.connect(alice).contributeICO(1, { value: ethers.parseEther("1") });
await c.connect(alice).claimIcoTokens(1);
```

## Threat Model and Assumptions

- `owner` is trusted to set `feeBps`, `feeRecipient`, reward base URI, and DAO address.
- If DAO approval is enabled, the DAO can approve or effectively block campaign funding.
- Campaign creators are trusted to deposit enough ICO tokens for intended sales.
- The system is non-upgradeable in its current form.
- This repository is educational and not externally audited.

## Security Notes

- Uses `ReentrancyGuard` on transfer-sensitive functions.
- Uses checks-effects-interactions in withdraw/refund flows.
- Uses `SafeERC20` for token transfers.
- ICO token pool accounting prevents overselling claims.

See `SECURITY.md` for disclosure guidance.
Detailed review: `docs/security-gas-review-v1.0.0.md`.

## Testing

- `test/crowdfunding.eth.test.js`
- `test/crowdfunding.erc20.test.js`
- `test/crowdfunding.ico.test.js`

## Deployment (Sepolia)

1. Copy `.env.example` to `.env`.
2. Set `SEPOLIA_RPC_URL` and `PRIVATE_KEY`.
3. Deploy:

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

## Roadmap

### Implemented

- [x] Platform fee
- [x] Campaign cancellation (pre-funding)
- [x] Minimum contribution
- [x] Whitelisted contributors
- [x] NFT rewards
- [x] ERC20-based ICO pricing
- [x] DAO-controlled campaign approval

### Planned

- [ ] Front-end demo dApp (campaign creation and contribution flow)
- [ ] Better on-chain metadata for campaigns
- [ ] Formalized governance flow for DAO management

### Out of Scope (Current Version)

- [ ] Production guarantees without external audit
- [ ] Multi-chain deployment orchestration in this repo

## Technical Write-up

- `docs/how-i-built-a-secure-ico-crowdfunding-smart-contract.md`

## License

MIT
