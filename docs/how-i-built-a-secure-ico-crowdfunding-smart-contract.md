# How I Built a Secure ICO / Crowdfunding Smart Contract

## Goal

The goal was to build a Kickstarter-style crowdfunding protocol on Ethereum that also supports token-sale style ICO campaigns, while keeping the design practical and security-focused.

## Architecture

Core contract: `contracts/Crowdfunding.sol`

Main building blocks:

- Campaign creation for ETH, ERC-20, and ICO campaigns
- Per-campaign accounting (`raised`, deadline, goal, status flags)
- Per-user accounting (`contributions`, whitelist membership, ICO token owed)
- Outcome execution (withdraw success path, refund failure path)
- Admin controls (fees, DAO gate, reward base URI)

The contract also inherits:

- `ReentrancyGuard` for transfer-sensitive functions
- `Ownable` for platform-level controls
- `ERC721` for optional contributor reward NFTs

## ETH vs ERC-20 Flow

### ETH Campaigns

- Creator opens campaign with `token = address(0)`
- Contributors call `contributeETH`
- If goal is reached, creator calls `withdraw`
- If deadline passes and goal is not reached, contributors call `refund`

### ERC-20 Campaigns

- Creator opens campaign with `token = <erc20>`
- Contributor approves tokens and calls `contributeToken`
- On success, creator withdraws tokens (platform fee can apply)
- On failure, contributor claims token refund

The key idea is that both flows share the same state model, with only transfer mechanics changing.

## ICO Flow and Pricing

ICO campaigns use ETH for funding and distribute ERC-20 sale tokens later:

1. Creator calls `createIcoCampaign` with a fixed `tokenPrice` (tokens per 1 ETH, scaled by `1e18`)
2. Creator deposits sale inventory with `depositIcoTokens`
3. Contributors fund using `contributeICO`
4. On successful campaign, contributors call `claimIcoTokens`
5. If campaign fails, contributors call `refund` and allocation is released

This design separates funding and token delivery while preventing overselling with explicit token pool accounting.

## Refund Design

Refunds follow a pull model:

- Contract never loops through all contributors
- Each contributor calls `refund` to retrieve their own funds
- Contribution balance is zeroed before external transfer

This avoids gas-scaling problems and follows checks-effects-interactions.

## Security Decisions

Main decisions that reduced risk:

- `nonReentrant` on withdraw/refund/ICO transfer functions
- `SafeERC20` for token interactions
- Explicit deadline/goal/cancel checks for all flows
- Single-withdraw guard (`withdrawn` flag)
- Fee cap (`MAX_FEE_BPS = 300`) to bound owner-controlled fees
- Optional DAO approval gate for campaign admission control
- ICO escrow accounting (`icoTokenPool`, `tokensSold`, `tokensClaimed`) to avoid undercollateralized claims

## Trade-offs

- Owner and DAO roles are trusted assumptions
- DAO gating can block campaigns (policy risk)
- NFT rewards add UX value but increase contract complexity
- ICO mode adds accounting complexity for stronger safety guarantees
- No upgradeability keeps trust surface smaller, but reduces flexibility for future on-chain fixes

## Testing Strategy

Test suites:

- `test/crowdfunding.eth.test.js`
- `test/crowdfunding.erc20.test.js`
- `test/crowdfunding.ico.test.js`

Coverage includes:

- Creation/contribution happy paths
- Deadline and goal edge cases
- Success withdraw and failure refunds
- Minimum contribution, whitelist, cancellation
- Fee collection
- ICO token deposit/contribution/claim/refund behavior

## Final Notes

This repository is intentionally educational and demonstrates production-inspired patterns, but it is not audited. For production deployment, perform independent security review and adversarial testing.
