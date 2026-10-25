#!/bin/sh
# Regenerates patches/0001-ayugram.patch from a Telegram-iOS checkout with the AyuGram changes.
#   scripts/make-patch.sh /path/to/Telegram-iOS
set -e
TG="${1:?path to the Telegram-iOS checkout}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/patches/0001-ayugram.patch"
cd "$TG"
git add -A -N submodules
git -c core.abbrev=8 diff --binary > "$OUT"
echo "Wrote $OUT"
