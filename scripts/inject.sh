#!/bin/bash
set -euo pipefail

IPA=${1:?usage: inject.sh <decrypted.ipa> [out.ipa]}
OUT=${2:-injected.ipa}
DYLIB=${DYLIB:-FreeFirePanel.dylib}
INS=${INS:-$(command -v insert_dylib || echo ./bin/insert_dylib)}
WORK=$(mktemp -d)

unzip -q "$IPA" -d "$WORK"
APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "no .app in payload"; exit 1; }
EXEC="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
echo "target: $EXEC"

codesign --remove-signature "$EXEC" 2>/dev/null || true
"$INS" --inplace --overwrite --strip-codesig \
    "@executable_path/Frameworks/$DYLIB" "$EXEC"

mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/$DYLIB"
codesign -f -s - "$APP/Frameworks/$DYLIB"

rm -rf "$APP/_CodeSignature"
(cd "$WORK" && zip -qry "$OLDPWD/$OUT" Payload)
rm -rf "$WORK"
echo "wrote $OUT"
