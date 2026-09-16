# Changelog

All notable changes to this project are documented in this file.

## [1.1.0.0] - 2026-09-16

### Added

- Add a GitHub Actions CI/CD pipeline that tests the exact commit, creates a checksummed immutable artifact, and deploys `main` through the protected `production` environment.
- Add least-privilege server bootstrap and SSH-hardening scripts for a dedicated `deploy` user with pinned host verification.
- Add atomic release and manual rollback operations with local and public health checks, SHA validation, and automatic restoration of the previous healthy release.
- Publish `/deploy-meta.json` as the static deployment provenance contract and document production variables, secrets, troubleshooting, and acceptance evidence.

### Changed

- Use `no-cache` for HTML and deployment metadata and revalidation for the unhashed CSS asset instead of `immutable` caching.

### Verification status

- Repository tests and isolated release-script tests are implemented.
- Production account permissions, SSH hardening, Nginx cache behavior, and GitHub `production` environment configuration have been verified.
- The first pushed Actions run, automatic deployment, failure rollback, manual rollback, and concurrency exercise remain pending; they are not claimed as production-verified.

## [1.0.0.0] - 2026-09-16

### Added

- Publish the first version of Zheng Wenze's personal homepage.
- Add the first long-form article about evidence-driven AI Infra learning.
- Add responsive styling, accessible navigation, deployment configuration, tests, and project documentation.
- Add a repeatable server installer with commit-addressed releases and an atomic Nginx switch.
