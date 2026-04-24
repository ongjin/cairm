#!/usr/bin/env bash
# Submit an app bundle or DMG to Apple notarization and staple the ticket.
set -euo pipefail

TARGET="${1:-}"
[ -e "$TARGET" ] || { echo "usage: $0 <path/to/Cairn.app|path/to/Cairn.dmg>" >&2; exit 1; }
: "${NOTARY_KEY_ID?NOTARY_KEY_ID not set}"
: "${NOTARY_ISSUER_ID?NOTARY_ISSUER_ID not set}"
: "${NOTARY_KEY_PATH?NOTARY_KEY_PATH not set}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SUBMISSION="$TARGET"
ASSESS_TYPE="open"
if [ -d "$TARGET" ]; then
    SUBMISSION="$WORK_DIR/Cairn.zip"
    ASSESS_TYPE="exec"
    ditto -c -k --keepParent "$TARGET" "$SUBMISSION"
fi

echo "Submitting to notarytool..."
xcrun notarytool submit "$SUBMISSION" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait

echo "Stapling ticket..."
xcrun stapler staple "$TARGET"

echo "Gatekeeper assessment:"
spctl --assess --type "$ASSESS_TYPE" --verbose=4 "$TARGET"

echo "Notarized: $TARGET"
