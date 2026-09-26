#!/usr/bin/env bash
# Full local verification, same order as CI (spec §14.1): toolchain → generate → lint → build → unit → UI.
# Fails fast by default; --keep-going runs every step and reports all failures (what CI does).
source "$(dirname "$0")/lib/common.sh"

keep_going=0
skip_ui=0
for arg in "$@"; do
    case "$arg" in
        --keep-going) keep_going=1 ;;
        --skip-ui) skip_ui=1 ;;
        *) fail "verify" "unknown argument $arg" "usage: Scripts/verify.sh [--keep-going] [--skip-ui]" ;;
    esac
done

require_macos "verify"
rm -f "$DEST_FILE"
results=""
failed=0
step() {
    local name="$1"
    shift
    if [ $failed -eq 1 ] && [ $keep_going -eq 0 ]; then
        results="$results\n  SKIP  $name"
        return
    fi
    if "$@"; then
        results="$results\n  PASS  $name"
    else
        results="$results\n  FAIL  $name"
        failed=1
    fi
}

toolchain() { (select_xcode); }
step "Toolchain" toolchain
step "Generate project" "$REPO_ROOT/Scripts/generate.sh"
step "Lint" "$REPO_ROOT/Scripts/lint.sh"
step "Build" "$REPO_ROOT/Scripts/build.sh"
export HH_SKIP_BUILD=1
step "Unit tests" "$REPO_ROOT/Scripts/test.sh"
if [ $skip_ui -eq 0 ]; then
    step "UI tests" "$REPO_ROOT/Scripts/ui-test.sh"
fi

section "verify summary"
printf '%b\n' "$results"
[ $failed -eq 0 ] || exit 1
