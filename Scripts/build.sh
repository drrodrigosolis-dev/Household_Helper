#!/usr/bin/env bash
# Builds app + test bundles for the iOS Simulator (build-for-testing) so test steps can run without rebuilding.
source "$(dirname "$0")/lib/common.sh"

section "Build for iOS Simulator"
select_xcode
resolve_destination
info "destination: $(destination)"
run_xcodebuild "Build" "build" "" build-for-testing -destination "$(destination)" -quiet
info "build: succeeded"
summary "- **Build** succeeded ($(destination))"
