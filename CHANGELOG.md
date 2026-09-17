# Changelog

All notable changes to this project are documented in this file.

## [1.1.0.0] - 2026-09-16

### Added

- Automatically test and deploy each accepted `main` commit from one checksummed, immutable artifact through the protected `production` environment.
- Keep routine deployments isolated from server administration with a dedicated least-privilege `deploy` account, pinned host verification, and guided SSH hardening.
- Switch releases atomically, restore the last healthy version after a failed check, and allow operators to roll back to any validated retained release.
- Expose `/deploy-meta.json` so an online page can be traced to its exact commit and Actions run, with operations and troubleshooting guidance included.

### Changed

- Use `no-cache` for HTML and deployment metadata and revalidation for the unhashed CSS asset instead of `immutable` caching.

### Verification status

- Repository tests and isolated release-script tests are implemented.
- Production account permissions, SSH hardening, Nginx cache behavior, and GitHub `production` environment configuration have been verified.
- PR-only CI, automatic production deployment, public SHA verification, manual rollback, latest-release restoration, and serialized concurrent deployments have been verified with GitHub Actions runs.
- Automatic restoration after a failed health check is verified by the isolated release-script test executed in CI; no artificial public outage was introduced.

## [1.0.0.0] - 2026-09-16

### Added

- Publish the first version of Zheng Wenze's personal homepage.
- Add the first long-form article about evidence-driven AI Infra learning.
- Add responsive styling, accessible navigation, deployment configuration, tests, and project documentation.
- Add a repeatable server installer with commit-addressed releases and an atomic Nginx switch.
