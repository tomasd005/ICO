# Crowdfunding Smart Contract (ICO / Kickstarter-style)

An Ethereum-based crowdfunding / ICO smart contract that allows project creators to raise funds in a trust-minimized, transparent way using ETH or ERC-20 tokens.

## Overview

This contract lets project creators launch fundraising campaigns and accept contributions in either ETH or a specific ERC-20 token. Funds are held by the contract until the campaign succeeds (goal reached) or fails (deadline reached without goal). Contributors can claim refunds in failed campaigns. Optional DeFi-style features include platform fees, DAO approvals, whitelisting, minimum contributions, NFT rewards, and fixed-price ICO sales.

## Architecture

```
Contributors (ETH/ERC20)
        |
        v
  Crowdfunding.sol
        |
        +-- Tracks campaigns + per-contributor balances
        +-- Optional DAO approval gate
        +-- Optional fee recipient
        +-- Optional reward NFT minting
        +-- ICO token escrow + claims
```

### Contracts

- `contracts/Crowdfunding.sol`: Main crowdfunding and ICO logic
- `contracts/MockERC20.sol`: Test token used by unit tests

### Core Data Structures

```
struct Campaign {
    address creator;
    uint256 goal;
    uint256 deadline;
    uint256 raised;
    bool withdrawn;
    address token; // address(0) for ETH, or ERC-20
    uint256 minContribution;
    bool cancelled;
    bool whitelistEnabled;
    bool rewardEnabled;
    bool approved;
    bool isIco;
    uint256 tokenPrice; // tokens per 1 ETH, scaled by 1e18
    uint256 tokensSold;
    uint256 tokensClaimed;
}
```

Mappings:

- `campaignId => Campaign`
- `campaignId => contributor => amount`
- `campaignId => contributor => whitelisted`
- `campaignId => contributor => icoOwed`

## MVP Features

- Campaign creation with funding goal, deadline, and accepted currency (ETH or ERC-20)
- ETH or ERC-20 contributions with per-contributor accounting
- Successful campaigns: creator can withdraw funds
- Failed campaigns: contributors can claim refunds

## Stretch Features Implemented

- Platform fee with configurable recipient (basis points)
- Campaign cancellation before any contributions
- Minimum contribution per campaign
- Whitelisted contributors
- NFT reward minted to contributors
- ERC20-based ICO pricing with fixed token-per-ETH price
- DAO-controlled campaign approval

## ICO Pricing Flow

ICO campaigns sell an ERC-20 token in exchange for ETH at a fixed price set by the creator.

- Use `createIcoCampaign` with `tokenPrice` expressed as tokens per 1 ETH (scaled by `1e18`).
- Creator deposits sale tokens via `depositIcoTokens` before contributions are accepted.
- Contributors call `contributeICO` with ETH and can later claim tokens via `claimIcoTokens`.
- If the campaign fails, contributors can refund ETH and their token allocation is released.

## Reward NFTs

- When `rewardEnabled` is true, a contributor receives one ERC-721 reward per campaign.
- The reward is minted on first contribution for that campaign.
- Base URI can be set by the contract owner via `setRewardBaseURI`.

## DAO Approval

- If `dao` is set to a non-zero address, new campaigns start unapproved.
- The DAO must call `approveCampaign` before contributions are accepted.

## Platform Fees

- Fees are configured in basis points with a hard cap of 3%.
- The owner sets the fee via `setFee(feeBps, feeRecipient)`.

## Security Considerations

- Checks-Effects-Interactions pattern
- Reentrancy protection on external transfers
- Pull-over-push refunds
- Deadline validation
- Single withdrawal guard
- Safe ERC-20 transfers via `SafeERC20`
- ICO token escrow accounting to prevent overselling

## Known Limitations

- No on-chain metadata (title/description) for campaigns
- No governance flow beyond DAO approval
- ICO tokens must be deposited before contributions are accepted

## Gas Considerations

- Per-contribution accounting uses a mapping keyed by campaign and contributor
- Events are emitted on creation, contribution, withdrawal, refund, and ICO actions for off-chain indexing

## Local Development

### Install

```bash
npm install
```

### Compile

```bash
npm run compile
```

### Test

```bash
npm test
```

Test files:

- `test/crowdfunding.eth.test.js`
- `test/crowdfunding.erc20.test.js`
- `test/crowdfunding.ico.test.js`

## Deployment (Sepolia)

1. Copy `.env.example` to `.env` and fill in `SEPOLIA_RPC_URL` and `PRIVATE_KEY`.
2. Run:

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

## License

MIT
