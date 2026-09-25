#!/usr/bin/env bash
# Generates HouseholdHub.xcodeproj from project.yml and confirms the scheme exists.
source "$(dirname "$0")/lib/common.sh"

section "Generate Xcode project"
require_macos "Generate project"
command -v xcodegen >/dev/null || fail "Generate project" "xcodegen not found." "brew install xcodegen (see docs/research/dependency-decisions.md)"
info "xcodegen $(xcodegen --version 2>/dev/null | tail -n1)"
xcodegen generate --spec project.yml --quiet || fail "Generate project" "xcodegen rejected project.yml (error above)."
[ -d "$PROJECT" ] || fail "Generate project" "$PROJECT was not created."
schemes="$(xcodebuild -list -project "$PROJECT" 2>&1)" || fail "Generate project" "xcodebuild -list failed: $schemes"
printf '%s\n' "$schemes" | grep -qE "^[[:space:]]+$SCHEME\$" \
    || fail "Generate project" "scheme '$SCHEME' missing from generated project." "Check the schemes: block in project.yml."
info "ok: $PROJECT with scheme $SCHEME"
