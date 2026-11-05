# Security Policy

PurseSecureFields collects cardholder data. A vulnerability here can put card data at risk, so
please report privately rather than in a public issue.

## Supported versions

| Version | Supported |
|---|---|
| 1.x (latest release) | Yes |
| Older 1.x releases | No — upgrade to the latest tag |

Only the most recent release receives security fixes. Versions follow semantic
versioning, derived from Conventional Commit subjects: a `fix:` is a patch, a
`feat:` a minor, and a `feat!:` or `BREAKING CHANGE:` a major. A major version
is the only place the public API may change incompatibly. Releases are published as a signed
XCFramework attached to each [GitHub release](https://github.com/UpStreamPay/purse-securefields-ios/releases).

## Reporting a vulnerability

**Do not open a public issue, pull request, or discussion for a security report.**

Use GitHub's private vulnerability reporting: go to the **Security** tab of this repository and
choose **Report a vulnerability**. The report stays private to you and the maintainers.

If you cannot use GitHub, email **contact@purse.eu** with `SecureFields iOS` in the subject.

Please include:

- affected SDK version and iOS version,
- steps to reproduce, or a proof of concept,
- the impact you believe it has — in particular whether raw PAN, CVV, or cardholder data is
  exposed to host application code.

### What to expect

- Acknowledgement within 3 business days.
- An initial assessment, including whether we consider it in scope, within 10 business days.
- A fix released in a patch version, with the advisory published once integrators have had a
  reasonable window to upgrade.

Please give us a chance to ship a fix before disclosing publicly.

## Scope

In scope:

- Card data (PAN, CVV, expiry, holder name) reaching host application code, logs, screenshots,
  pasteboard, or crash reports.
- Bypassing TLS certificate pinning (`SecureFieldsConfig.pinnedPublicKeyHashes`).
- Tampering with the tokenization request or response handled by `VaultAPIClient`.
- Anything that weakens the field isolation described in [`docs/security/security.md`](docs/security/security.md).

Out of scope:

- Findings that require a jailbroken device or a debugger attached to the host application.
- Integrations that do not follow the hardening steps in
  [`docs/security/security.md`](docs/security/security.md) — for example shipping without
  certificate pinning configured.
- Vulnerabilities in the Demo application that do not affect the SDK target.

## PCI DSS

For PCI DSS scope questions rather than a vulnerability report, see
[`docs/security/security.md`](docs/security/security.md) and share it with your QSA.
