#!/usr/bin/env bash
# Runs UI tests (XCTest/XCUIAutomation, HouseholdHubUITests). HH_SKIP_BUILD=1 reuses the build from Scripts/build.sh.
source "$(dirname "$0")/lib/common.sh"

skip_build || "$REPO_ROOT/Scripts/build.sh"
section "UI tests (HouseholdHubUITests)"
select_xcode >/dev/null
resolve_destination
bundle="$RESULTS_DIR/ui.xcresult"
run_xcodebuild "UI tests" "ui-tests" "$bundle" test-without-building \
    -destination "$(destination)" -only-testing:HouseholdHubUITests
report_test_counts "$bundle" "UI tests"
