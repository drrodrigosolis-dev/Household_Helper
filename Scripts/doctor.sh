#!/usr/bin/env bash
# Prints an environment report (spec §16.3). Read-only; never installs anything.
source "$(dirname "$0")/lib/common.sh"

row() { printf '    %-28s %-26s %s\n' "$1" "$2" "${3:-}"; }
tool() {
    local name="$1" cmd="$2"
    if command -v "${cmd%% *}" >/dev/null 2>&1; then
        row "$name" "AVAILABLE" "$($cmd 2>&1 | head -n1)"
    else
        row "$name" "NOT INSTALLED"
    fi
}

section "Environment report"
row "Host" "$(uname -s)" "$(uname -m)"
if [ "$(uname -s)" = "Darwin" ]; then
    row "macOS" "AVAILABLE" "$(sw_vers -productVersion)"
    for app in /Applications/Xcode*.app; do
        [ -d "$app" ] || continue
        row "$(basename "$app")" "installed" \
            "SDK $(DEVELOPER_DIR="$app/Contents/Developer" xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo '?')"
    done
    tool "xcodebuild" "xcodebuild -version"
    tool "swift" "swift --version"
    if xcrun --find swift-format >/dev/null 2>&1; then row "swift-format" "AVAILABLE" "$(xcrun swift-format --version 2>&1)"; else row "swift-format" "NOT INSTALLED"; fi
    section "iOS simulator runtimes"
    xcrun simctl list runtimes 2>/dev/null | grep -i ios | sed 's/^/    /' || row "runtimes" "UNKNOWN"
    section "Available iPhone simulators"
    xcrun simctl list devices available 2>/dev/null | grep -E "iPhone|-- iOS" | head -30 | sed 's/^/    /' || true
else
    row "Xcode / iOS Simulator" "NOT AVAILABLE HERE" "verified via CI (.github/workflows/verify.yml)"
fi
tool "git" "git --version"
tool "xcodegen" "xcodegen --version"
tool "python3" "python3 --version"
tool "claude" "claude --version"
tool "gh" "gh --version"
row "Repo remote" "" "$(git remote get-url origin 2>/dev/null || echo none)"
row "Branch" "" "$(git rev-parse --abbrev-ref HEAD)"
row "Physical device / Personal Team" "UNKNOWN" "not required (spec §11)"
