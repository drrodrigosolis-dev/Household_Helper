#!/usr/bin/env bash
# PostToolUse: lint (never rewrite) an edited Swift file with swift-format. Exit 2 feeds findings back to Claude.
# No-op off macOS; CI's lint step is the enforcing gate.
set -uo pipefail

file="$(python3 -c 'import json,sys; d=json.load(sys.stdin); i=d.get("tool_input") or {}; print(i.get("file_path",""))' 2>/dev/null)"
case "$file" in
    *.swift) ;;
    *) exit 0 ;;
esac
[ -f "$file" ] || exit 0
command -v xcrun >/dev/null 2>&1 || exit 0
xcrun --find swift-format >/dev/null 2>&1 || exit 0

root="$(cd "$(dirname "$0")/../.." && pwd)"
if ! out="$(cd "$root" && xcrun swift-format lint --strict "$file" 2>&1)"; then
    printf 'swift-format lint findings in %s (fix by hand or run Scripts/format.sh):\n%s\n' "$file" "$out" >&2
    exit 2
fi
exit 0
