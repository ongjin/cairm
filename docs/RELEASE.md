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
