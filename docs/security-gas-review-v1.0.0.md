# Security and Gas Review (v1.0.0)

Date: 2026-02-08

## Scope

- `contracts/Crowdfunding.sol`
- `contracts/MockERC20.sol`

## Tooling

- Slither `0.11.5`
- Hardhat gas reporter (via `REPORT_GAS=true npm test`)

## Commands Used

```bash
# Static analysis
/tmp/slither-venv/bin/slither . --filter-paths "node_modules|cache|artifacts|test"

# Gas profiling
REPORT_GAS=true npm test
```

## High-Level Result

- No critical findings identified in project contracts.
- No high severity findings identified in project contracts.
- Remaining findings are expected-design or hardening-oriented.

## Findings (Open)

1. `timestamp` (Informational)
- Affected logic: campaign deadlines and contribution windows.
- References: `contracts/Crowdfunding.sol:120`, `contracts/Crowdfunding.sol:166`, `contracts/Crowdfunding.sol:342`, `contracts/Crowdfunding.sol:395`, `contracts/Crowdfunding.sol:424`.
- Assessment: expected for crowdfunding/ICO deadline enforcement.
- Mitigation: keep reasonable buffers around deadlines in UX.

2. `low-level-calls` (Informational)
- Affected logic: ETH payout/refund uses `.call`.
- References: `contracts/Crowdfunding.sol:373`, `contracts/Crowdfunding.sol:381`, `contracts/Crowdfunding.sol:413`.
- Assessment: intentional pattern for ETH transfer compatibility.
- Existing protections: checks-effects-interactions + `nonReentrant` on payout/refund functions.

3. `cyclomatic-complexity` in `withdraw` (Low)
- Reference: `contracts/Crowdfunding.sol:356`.
- Assessment: function handles ETH/ERC20 + fee branch + ICO reserved-token guard, increasing branch count.
- Recommendation: split into internal helpers (`_withdrawEth`, `_withdrawToken`, `_transferFee`) for readability and auditability.

## Findings Addressed During This Review

1. `missing-zero-check` on DAO setter
- Change: `setDao` now rejects `address(0)` and `clearDao()` was added for explicit DAO disable.
- References: `contracts/Crowdfunding.sol:230`, `contracts/Crowdfunding.sol:235`.

2. `unindexed-event-address`
- Change: `FeeUpdated` and `DaoUpdated` now index address fields.
- References: `contracts/Crowdfunding.sol:70`, `contracts/Crowdfunding.sol:71`.

3. Reentrancy hardening on contribution paths with NFT mint callback
- Change: added `nonReentrant` to `contributeETH` and `contributeICO`.
- References: `contracts/Crowdfunding.sol:261`, `contracts/Crowdfunding.sol:286`.

## Gas Snapshot (Test Suite Derived)

### Deployments

- `Crowdfunding`: `2,892,194` gas
- `MockERC20`: `567,510` gas

### Heaviest methods (average)

- `createIcoCampaign`: `194,830`
- `createCampaign`: `162,731`
- `contributeICO`: `122,396`
- `contributeToken`: `111,268`
- `claimIcoTokens`: `94,164`
- `contributeETH`: `89,780` (max `180,485` when reward mint path is hit)

### Lower-cost paths (average)

- `withdraw`: `71,151`
- `withdrawIcoTokens`: `56,438`
- `setFee`: `53,442`
- `setDao`: `47,634`
- `refund`: `49,316`

## Practical Recommendations

1. Keep using Node LTS (`20.x`/`22.x`) for deterministic Hardhat behavior.
2. If prioritizing gas, make reward NFT optional per campaign (already supported) and disable for low-value campaigns.
3. Consider refactoring `withdraw` into smaller internal functions before any external audit.
4. Re-run Slither + gas snapshot before each tagged release.

## Disclaimer

This review is static-analysis-assisted and test-driven, not a formal third-party audit.
