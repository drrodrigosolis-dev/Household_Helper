#!/usr/bin/env bash
# Runs UI tests (XCTest/XCUIAutomation, HouseholdHubUITests). HH_SKIP_BUILD=1 reuses the build from Scripts/build.sh.
# Screenshot attachments are exported to build/screenshots/<name>.png for the sprint walk, pass or fail.
source "$(dirname "$0")/lib/common.sh"

skip_build || "$REPO_ROOT/Scripts/build.sh"
section "UI tests (HouseholdHubUITests)"
select_xcode >/dev/null
resolve_destination
bundle="$RESULTS_DIR/ui.xcresult"
screens="$BUILD_DIR/screenshots"

export_screenshots() {
    [ -d "$bundle" ] || return 0
    rm -rf "$screens"
    mkdir -p "$screens"
    if ! xcrun xcresulttool export attachments --path "$bundle" --output-path "$screens" >/dev/null 2>&1; then
        info "screenshot export unavailable (xcresulttool export attachments failed)"
        return 0
    fi
    # Rename exported files to the attachment names given in the tests (manifest.json maps them).
    python3 - "$screens" <<'PY'
import json, os, sys
root = sys.argv[1]
manifest = os.path.join(root, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for item in test.get("attachments", []):
            src = os.path.join(root, item.get("exportedFileName", ""))
            name = item.get("suggestedHumanReadableName") or ""
            base = name.split("_0_")[0] if "_0_" in name else os.path.splitext(name)[0]
            if base and os.path.exists(src):
                os.replace(src, os.path.join(root, base + os.path.splitext(src)[1]))
PY
    info "screenshots: $(find "$screens" -name '*.png' | wc -l | tr -d ' ') exported to ${screens#"$REPO_ROOT"/}"
}
trap export_screenshots EXIT

run_xcodebuild "UI tests" "ui-tests" "$bundle" test-without-building \
    -destination "$(destination)" -only-testing:HouseholdHubUITests
report_test_counts "$bundle" "UI tests"
