# Crowdfunding Smart Contract (ICO / Kickstarter-style)

An Ethereum-based crowdfunding / ICO smart contract that allows project creators to raise funds in a trust-minimized, transparent way using ETH or ERC-20 tokens.

## Overview

This contract lets project creators launch fundraising campaigns and accept contributions in either ETH or a specific ERC-20 token. Funds are held by the contract until the campaign succeeds (goal reached) or fails (deadline reached without goal). Contributors can claim refunds in failed campaigns.

## Architecture

```
Contributors (ETH/ERC20)
        |
        v
  Crowdfunding.sol
        |
        +-- Tracks campaigns + per-contributor balances
        |
        +-- Success: creator withdraws
        |
        +-- Failure: contributors refund
```

### Contracts

- `contracts/Crowdfunding.sol`: Main crowdfunding logic
- `contracts/MockERC20.sol`: Test token used by unit tests

### Core Data Structures

```
struct Campaign {
    address creator;
    uint256 goal;
    uint256 deadline;
    uint256 raised;
    bool withdrawn;
    address token; // address(0) for ETH
}
```

Mappings:

- `campaignId => Campaign`
- `campaignId => contributor => amount`

## MVP Features

- Campaign creation with funding goal, deadline, and accepted currency (ETH or ERC-20)
- ETH or ERC-20 contributions with per-contributor accounting
- Successful campaigns: creator can withdraw funds
- Failed campaigns: contributors can claim refunds

## Security Considerations

- Checks-Effects-Interactions pattern
- Reentrancy protection on external transfers
- Pull-over-push refunds
- Deadline validation
- Single withdrawal guard
- Safe ERC-20 transfers via `SafeERC20`

## Known Limitations

- No campaign cancellation feature
- No platform fees
- No minimum contribution or whitelist logic
- No on-chain metadata (title/description) for campaigns

## Gas Considerations

- Per-contribution accounting uses a mapping keyed by campaign and contributor
- Events are emitted on creation, contribution, withdrawal, and refund for off-chain indexing

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

## Deployment (Sepolia)

1. Copy `.env.example` to `.env` and fill in `SEPOLIA_RPC_URL` and `PRIVATE_KEY`.
2. Run:

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

## Stretch Features (Not Implemented)

- Platform fee
- Campaign cancellation
- Minimum contribution amount
- Whitelisted contributors
- NFT reward for contributors
- ERC20-based ICO pricing
- DAO-controlled campaign approval

## License

MIT
