# Release runbook

## One-time setup

1. Generate an App Store Connect API key with the Admin role and download the `.p8`.
2. Store it at `~/.config/cairn/notary.p8` outside the repository.
3. Export release credentials in your shell:

```sh
export NOTARY_KEY_ID=XXXXXXXXXX
export NOTARY_ISSUER_ID=00000000-0000-0000-0000-000000000000
export NOTARY_KEY_PATH=~/.config/cairn/notary.p8
export DEV_IDENTITY=<SHA1 of Developer ID Application cert>
```

## Sparkle signing (one-time)

Generate an EdDSA key pair with Sparkle's `generate_keys` tool:

```sh
./bin/generate_keys
```

Store the private key as `sparkle_signing_key.pem` at the repository root. This file is ignored by git and must never be committed.

Embed the printed public key in the app by adding this key to `apps/project.yml` under `targets.Cairn.info.properties`:

```yaml
SUPublicEDKey: <base64 public key>
```

Place Sparkle's `sign_update` tool at `./bin/sign_update`, or set `SPARKLE_SIGN_UPDATE=/path/to/sign_update` when generating the appcast.

## Required GitHub Secrets

- `APPLE_CERT_P12_BASE64` and `APPLE_CERT_PASSWORD` - Developer ID Application certificate.
- `DEV_IDENTITY_SHA1` - SHA1 of the certificate above.
- `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, and `NOTARY_KEY_P8_BASE64` - notarytool API key.
- `SPARKLE_PRIVATE_KEY_BASE64` - base64 of `sparkle_signing_key.pem`.
