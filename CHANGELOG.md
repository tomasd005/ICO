# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [1.0.0] - 2026-02-08

### Added

- Node LTS pinning via `.nvmrc` and `package.json` engines
- Technical write-up in `docs/how-i-built-a-secure-ico-crowdfunding-smart-contract.md`
- README link to the technical write-up

### Changed

- Project frozen as final portfolio version (`v1.0.0`)

## [0.1.0] - 2026-02-08

### Added

- Core crowdfunding campaigns for ETH and ERC-20
- Refund and withdrawal flows
- Platform fee support
- Campaign cancellation and minimum contribution checks
- Optional whitelist and DAO approval gate
- Contributor reward NFTs (ERC-721)
- ICO campaigns with fixed token-per-ETH pricing and token claim flow
- Hardhat tests for ETH, ERC-20, and ICO scenarios
- CI workflow for compile + test
