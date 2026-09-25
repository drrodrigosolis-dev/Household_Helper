#!/usr/bin/env bash
# Checks (never installs) the tools this project needs (spec §16.1) and prints install hints.
source "$(dirname "$0")/lib/common.sh"

section "Bootstrap check"
missing=0
check() {
    local name="$1" probe="$2" hint="$3"
    if eval "$probe" >/dev/null 2>&1; then
        info "ok       $name"
    else
        info "MISSING  $name  -> $hint"
        missing=$((missing + 1))
    fi
}
check git "command -v git" "xcode-select --install"
if [ "$(uname -s)" = "Darwin" ]; then
    check xcodebuild "command -v xcodebuild" "Install Xcode 26+ from the Mac App Store"
    check swift "command -v swift" "Ships with Xcode"
    check swift-format "xcrun --find swift-format" "Ships with Xcode 16+ toolchains"
    check xcodegen "command -v xcodegen" "brew install xcodegen"
    check claude "command -v claude" "curl -fsSL https://claude.ai/install.sh | bash"
else
    info "Not macOS: Xcode, swift, swift-format are unavailable here. CI (verify.yml) is the gate."
fi
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    info "WARNING  ANTHROPIC_API_KEY is set. This project uses subscription auth only (spec §15.1); unset it."
fi
[ $missing -eq 0 ] || fail "Bootstrap" "$missing tool(s) missing (see hints above). Nothing was installed."
info "bootstrap: all required tools present"
