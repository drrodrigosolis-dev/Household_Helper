#!/usr/bin/env bash
# Non-mutating checks: spec split in sync, shell syntax, Swift formatting/lint (swift-format from the Xcode toolchain).
source "$(dirname "$0")/lib/common.sh"

section "Lint"
status=0

info "spec split (docs/spec vs source spec)"
if ! python3 Scripts/split-spec.py --check; then
    in_ci && echo "::error title=Spec split drift::docs/spec is out of sync; run python3 Scripts/split-spec.py"
    status=1
fi

info "shell syntax (bash -n)"
for f in Scripts/*.sh Scripts/lib/*.sh .claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f"; then
        in_ci && echo "::error file=$f::bash syntax error"
        status=1
    fi
done
if command -v shellcheck >/dev/null; then
    # shellcheck disable=SC2046
    shellcheck -S warning -x $(ls Scripts/*.sh Scripts/lib/*.sh .claude/hooks/*.sh 2>/dev/null) || status=1
else
    info "shellcheck not installed; skipped (optional)"
fi

info "swift-format lint --strict"
if [ "$(uname -s)" = "Darwin" ]; then
    out="$LOG_DIR/swift-format.log"
    # shellcheck disable=SC2086
    if ! xcrun swift-format lint --strict --recursive --parallel $SWIFT_DIRS >"$out" 2>&1; then
        grep -E "(warning|error):" "$out" | head -60 >&2 || cat "$out" >&2
        if in_ci; then
            python3 - "$out" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    m = re.match(r"^(?:.*/Household_Helper/)?([^:]+):(\d+):(\d+): (?:warning|error): (.*)$", line.strip())
    if m:
        print("::error file=%s,line=%s,col=%s,title=swift-format::%s" % m.groups())
PY
            summary "### ❌ swift-format lint" "Run \`Scripts/format.sh\` on a Mac, or fix the listed lines by hand."
        fi
        status=1
    else
        info "swift-format: clean"
    fi
else
    info "swift-format skipped: not macOS (CI enforces it)"
fi

[ $status -eq 0 ] || fail "Lint" "one or more lint checks failed (details above)."
info "lint: all checks passed"
