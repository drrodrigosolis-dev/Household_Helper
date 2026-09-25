#!/usr/bin/env bash
# Runs unit/domain tests (Swift Testing, HouseholdHubTests). HH_SKIP_BUILD=1 reuses the build from Scripts/build.sh.
source "$(dirname "$0")/lib/common.sh"

skip_build || "$REPO_ROOT/Scripts/build.sh"
section "Unit tests (HouseholdHubTests)"
select_xcode >/dev/null
resolve_destination
bundle="$RESULTS_DIR/unit.xcresult"
run_xcodebuild "Unit tests" "unit-tests" "$bundle" test-without-building \
    -destination "$(destination)" -only-testing:HouseholdHubTests
report_test_counts "$bundle" "Unit tests"
