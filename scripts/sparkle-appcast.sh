#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}" DMG="${2:-}" NOTES_URL="${3:-}"
[ -n "$VERSION" ] && [ -f "$DMG" ] && [ -n "$NOTES_URL" ] || {
    echo "usage: $0 <version> <dmg-path> <release-notes-url>" >&2
    exit 1
}

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-./bin/sign_update}"
SIGNING_KEY="${SPARKLE_SIGNING_KEY:-sparkle_signing_key.pem}"
[ -x "$SIGN_UPDATE" ] || { echo "error: sign_update not found at $SIGN_UPDATE" >&2; exit 1; }
[ -f "$SIGNING_KEY" ] || { echo "error: Sparkle private key not found at $SIGNING_KEY" >&2; exit 1; }

SIZE=$(stat -f%z "$DMG")
DMG_URL="https://github.com/ongjin/cairn/releases/download/v${VERSION}/$(basename "$DMG")"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
SIG=$("$SIGN_UPDATE" --ed-key-file "$SIGNING_KEY" "$DMG" | head -1)

cat <<XML > appcast.xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cairn</title>
    <link>https://github.com/ongjin/cairn</link>
    <item>
      <title>Version $VERSION</title>
      <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="$DMG_URL"
        sparkle:version="$VERSION"
        sparkle:shortVersionString="$VERSION"
        length="$SIZE"
        type="application/octet-stream"
        $SIG />
    </item>
  </channel>
</rss>
XML

echo "Wrote appcast.xml"
