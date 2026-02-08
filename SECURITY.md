# Security Policy

## Security Status

This repository is an educational/demo smart contract project.

- It has not been professionally audited.
- It is not production-ready by default.
- Do not deploy this code with real assets without independent security review and testing.

## Supported Versions

Only the latest `main` branch is considered supported for security fixes.

## Reporting a Vulnerability

Please report vulnerabilities privately to the maintainer before opening a public issue.

Suggested report format:

- Affected file/function
- Impact and exploit scenario
- Reproduction steps or proof of concept
- Recommended mitigation

Do not publish proof-of-concept exploits before a fix is available.

## Security Assumptions

- Owner role is trusted to set fee parameters, DAO address, and reward base URI.
- DAO (if configured) is trusted to approve campaigns fairly.
- Users should verify campaign parameters (token, deadline, min contribution) before contributing.
