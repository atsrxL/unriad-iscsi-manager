#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
DIST="$ROOT/dist"
STAGE="$ROOT/.build/root"
NAME="unraid-iscsi-manager"

[[ "$VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}([a-z0-9.-]+)?$ ]] || {
  echo "Invalid VERSION: $VERSION" >&2
  exit 1
}

rm -rf "$ROOT/.build" "$DIST"
mkdir -p "$STAGE" "$DIST"
cp -a "$ROOT/src/." "$STAGE/"
chmod 0755 "$STAGE/usr/local/emhttp/plugins/$NAME/scripts/"*.sh

# Unraid's generateContent() runs .page bodies through Markdown by default when
# the Markdown header is omitted. These plugin pages contain raw PHP/HTML/JS,
# so force Markdown="false" in every staged page that has a body separator.
for page in "$STAGE/usr/local/emhttp/plugins/$NAME/"*.page; do
  [[ -f "$page" ]] || continue
  grep -q '^---$' "$page" || continue
  header="$(sed -n '1,/^---$/p' "$page")"
  if ! grep -q '^Markdown=' <<< "$header"; then
    tmp="${page}.tmp"
    awk 'BEGIN{done=0} /^---$/ && !done {print "Markdown=\"false\""; done=1} {print}' "$page" > "$tmp"
    mv "$tmp" "$page"
  fi
done

PACKAGE="$DIST/$NAME-$VERSION.txz"
PLG="$DIST/$NAME.plg"

tar --owner=0 --group=0 --numeric-owner -C "$STAGE" -cJf "$PACKAGE" .
MD5="$(md5sum "$PACKAGE" | awk '{print $1}')"

sed \
  -e "s/@VERSION@/$VERSION/g" \
  -e "s/@PACKAGE_MD5@/$MD5/g" \
  "$ROOT/plugin/$NAME.plg.in" > "$PLG"

printf 'Built:\n  %s\n  %s\nMD5: %s\n' "$PACKAGE" "$PLG" "$MD5"
