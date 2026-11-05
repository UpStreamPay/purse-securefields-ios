# Contributing

Thanks for considering a contribution to PurseSecureFields.

This SDK sits in the cardholder data path. That shapes what we can accept and how
quickly: changes touching field isolation, the tokenization request, TLS pinning
or the monitoring payload get a slower, closer review than the rest. Please open
an issue before starting anything substantial, so we can tell you early whether a
change is likely to be accepted.

## Before you start

- **Security issues do not belong in a pull request.** Report them privately —
  see [SECURITY.md](SECURITY.md).
- For a bug, open an issue with the SDK version, iOS version and a reproduction.
- For a feature, open an issue describing the integration problem you are hitting.
  We keep this SDK deliberately small.

## Getting set up

```bash
git clone https://github.com/UpStreamPay/purse-securefields-ios.git
cd purse-securefields-ios
xcodebuild test -scheme PurseSecureFields -destination 'platform=iOS Simulator,name=iPhone 17'
```

`swift build` will not work — the SDK is UIKit-based and iOS-only, so it has to be
built against a simulator SDK.

To run the demo app and its UI tests:

```bash
cp .env.example .env          # fill in TENANT_ID; leave MONITORING_API_KEY blank
source scripts/load-env.sh
xcodebuild test -project Demo/Demo.xcodeproj -scheme DemoUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

[`docs/contributing/internals.md`](docs/contributing/internals.md) explains the
field layer, BIN detection, tokenization and monitoring if you need the internals.

## Making a change

1. Fork the repository and branch from `main`.
2. Keep the change focused. One concern per pull request.
3. Add or update tests. Anything touching validation, the wire payload or field
   isolation needs a test that fails without your change.
4. Run both suites (library and demo UI) locally before pushing.
5. Use [Conventional Commits](https://www.conventionalcommits.org) for the commit
   subject — `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `test:`. Releases and
   the changelog are generated from these, so the subject is published verbatim.
   Write it for someone reading the release notes.

## What happens next

Pull requests need one approving review from the code owners before merging, and
CI (library tests and demo UI tests) must pass. We aim to give an initial response
within five working days.

Changes we are unlikely to accept:

- New third-party dependencies. The SDK ships with none, and that is deliberate.
- Anything that exposes raw field values (PAN, CVV, expiry, cardholder name)
  through a public API.
- Making `SecureBaseField` or its subclasses public.

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
