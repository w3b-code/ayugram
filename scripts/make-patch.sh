#!/bin/sh
# Regenerates patches/<tag>/0001-ayugram.patch from a Telegram-iOS checkout with the AyuGram changes.
#   scripts/make-patch.sh /path/to/Telegram-iOS [release-13.1.1]
# Without a tag, the checkout's own tag is used.
set -e
TG="${1:?path to the Telegram-iOS checkout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TG"
TAG="${2:-$(git describe --tags --exact-match)}"
OUT="$ROOT/patches/$TAG/0001-ayugram.patch"
mkdir -p "$(dirname "$OUT")"
git add -A -N submodules Telegram
git -c core.abbrev=8 diff --binary > "$OUT"
echo "Wrote $OUT"
