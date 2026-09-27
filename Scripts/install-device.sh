#!/usr/bin/env bash
# Builds Household Hub (Release) for a connected iPhone and installs it, signed by the free Personal Team (CLAUDE.md
# §2). The Team ID stays out of git: pass it per run. Free provisioning lasts 7 days; rerun this to reinstall, the
# app's data stays on the phone.
#
#   HH_TEAM=<Team ID> Scripts/install-device.sh "<iPhone name or UDID>"
#
# If Xcode says the bundle ID is taken, add HH_BUNDLE_PREFIX=<your own reverse-DNS prefix> (default dev.householdhub).
# Team ID: Xcode › Settings › Accounts › your Apple ID › Personal Team. Device name: `xcrun devicectl list devices`.
# On the iPhone, once: Settings › Privacy & Security › Developer Mode on; after the first install,
# Settings › General › VPN & Device Management › Apple Development › Trust.
source "$(dirname "$0")/lib/common.sh"

section "Install on iPhone"
select_xcode
device="${1:-}"
if [ -z "$device" ]; then
    xcrun devicectl list devices >&2 || true
    fail "Install" "no device given." "Pass the iPhone's name or UDID from the list above as the first argument."
fi
[ -n "${HH_TEAM:-}" ] || fail "Install" "HH_TEAM is not set." \
    "Xcode › Settings › Accounts › Personal Team shows the Team ID; run HH_TEAM=<id> Scripts/install-device.sh \"$device\"."
[ -d "$PROJECT" ] || "$REPO_ROOT/Scripts/generate.sh"

prefix="${HH_BUNDLE_PREFIX:-dev.householdhub}"
info "device: $device, bundle prefix: $prefix"
run_xcodebuild "Device build" "device-build" "" build -configuration Release -destination "generic/platform=iOS" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$HH_TEAM" BUNDLE_ID_PREFIX="$prefix"
app="$DERIVED_DATA/Build/Products/Release-iphoneos/HouseholdHub.app"
[ -d "$app" ] || fail "Install" "built app not found at ${app#$REPO_ROOT/}."
info "built: ${app#$REPO_ROOT/} ($(git rev-parse --short HEAD))"

xcrun devicectl device install app --device "$device" "$app" \
    || fail "Install" "devicectl could not install the app." \
        "Unlock the iPhone, keep it connected, and check Developer Mode is on."
info "installed"
xcrun devicectl device process launch --device "$device" "$prefix.app" \
    || info "Not launched: trust the developer on the iPhone (Settings › General › VPN & Device Management), then open it."
