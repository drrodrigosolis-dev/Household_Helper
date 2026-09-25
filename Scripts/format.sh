#!/usr/bin/env bash
# Rewrites Swift sources in place with swift-format. Explicit action only; hooks never call this.
source "$(dirname "$0")/lib/common.sh"

section "Format (in place)"
require_macos "Format"
# shellcheck disable=SC2086
xcrun swift-format format --in-place --recursive --parallel $SWIFT_DIRS
info "formatted: $SWIFT_DIRS"
