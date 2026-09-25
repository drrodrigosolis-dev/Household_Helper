#!/usr/bin/env bash
# Shared helpers for Scripts/*.sh. Must stay bash 3.2 compatible (macOS /bin/bash).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PROJECT="HouseholdHub.xcodeproj"
SCHEME="HouseholdHub"
MIN_IOS_SDK="26.0"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
RESULTS_DIR="$BUILD_DIR/results"
LOG_DIR="$BUILD_DIR/logs"
DEST_FILE="$BUILD_DIR/.destination"
# shellcheck disable=SC2034  # consumed by lint.sh/format.sh
SWIFT_DIRS="HouseholdHubCore HouseholdHubApp HouseholdHubTests HouseholdHubUITests"
# Simulator preference: spec §27 reference device first, then newer Pro Max models.
PREFERRED_DEVICES="iPhone 16 Pro Max|iPhone 17 Pro Max|iPhone 17 Pro|iPhone 16 Pro|iPhone 17|iPhone 16"

mkdir -p "$BUILD_DIR" "$RESULTS_DIR" "$LOG_DIR"

in_ci() { [ "${GITHUB_ACTIONS:-}" = "true" ]; }

section() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

# fail STEP MESSAGE [HINT] — prints a diagnostic block, annotates in CI, exits 1.
fail() {
    local step="$1" msg="$2" hint="${3:-}"
    printf '\n[FAIL] %s: %s\n' "$step" "$msg" >&2
    [ -n "$hint" ] && printf '       Hint: %s\n' "$hint" >&2
    if in_ci; then
        echo "::error title=${step} failed::${msg}"
        summary "### ❌ ${step} failed" "" "${msg}" "" "${hint:+Hint: $hint}"
    fi
    exit 1
}

summary() {
    if in_ci && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"
    fi
}

require_macos() {
    [ "$(uname -s)" = "Darwin" ] || fail "$1" "requires macOS with Xcode; this host is $(uname -s)." \
        "No session is assumed to have Xcode. Push to build/v1 and read .github/workflows/verify.yml results instead."
}

# Picks the newest installed Xcode whose iOS Simulator SDK >= MIN_IOS_SDK and exports DEVELOPER_DIR.
select_xcode() {
    require_macos "Select Xcode"
    if [ -n "${DEVELOPER_DIR:-}" ] && [ -d "$DEVELOPER_DIR" ]; then
        info "Using preset DEVELOPER_DIR=$DEVELOPER_DIR"
        return 0
    fi
    local best="" best_ver="0" app dev ver
    for app in /Applications/Xcode*.app; do
        [ -d "$app" ] || continue
        dev="$app/Contents/Developer"
        ver="$(DEVELOPER_DIR="$dev" xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || true)"
        [ -n "$ver" ] || continue
        info "found $(basename "$app") (iphonesimulator SDK $ver)"
        if version_ge "$ver" "$MIN_IOS_SDK" && version_ge "$ver" "$best_ver"; then
            best="$dev"
            best_ver="$ver"
        fi
    done
    if [ -z "$best" ]; then
        local current
        current="$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo none)"
        if [ "$current" != "none" ] && version_ge "$current" "$MIN_IOS_SDK"; then
            best="$(xcode-select -p)"
            best_ver="$current"
        else
            fail "Select Xcode" "no installed Xcode has an iOS Simulator SDK >= $MIN_IOS_SDK." \
                "Project targets iOS $MIN_IOS_SDK (spec §0). The runner image may lack Xcode 26; check runs-on image or install one."
        fi
    fi
    export DEVELOPER_DIR="$best"
    info "Selected DEVELOPER_DIR=$DEVELOPER_DIR (SDK $best_ver)"
    if in_ci && [ -n "${GITHUB_ENV:-}" ]; then
        echo "DEVELOPER_DIR=$DEVELOPER_DIR" >>"$GITHUB_ENV"
    fi
    xcodebuild -version | sed 's/^/    /'
}

version_ge() {
    # version_ge A B → true if A >= B (dotted numeric).
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" = "$2" ]
}

# Resolves an iPhone simulator on an iOS runtime >= MIN_IOS_SDK; writes "id=<udid>" to DEST_FILE.
resolve_destination() {
    require_macos "Resolve simulator"
    if [ -n "${HH_DESTINATION:-}" ]; then
        echo "$HH_DESTINATION" >"$DEST_FILE"
        return 0
    fi
    if [ -s "$DEST_FILE" ]; then
        return 0
    fi
    local picked
    picked="$(pick_simulator || true)"
    if [ -z "$picked" ] && in_ci; then
        info "No iOS >= $MIN_IOS_SDK simulator runtime found; attempting 'xcodebuild -downloadPlatform iOS' once."
        xcodebuild -downloadPlatform iOS || true
        picked="$(pick_simulator || true)"
    fi
    if [ -z "$picked" ]; then
        xcrun simctl list runtimes >&2 || true
        fail "Resolve simulator" "no iPhone simulator with iOS >= $MIN_IOS_SDK is available (runtimes listed above)." \
            "Install an iOS $MIN_IOS_SDK+ simulator runtime (Xcode > Settings > Components)."
    fi
    echo "platform=iOS Simulator,id=${picked%%|*}" >"$DEST_FILE"
    info "Simulator: ${picked#*|}"
}

pick_simulator() {
    xcrun simctl list devices available --json | python3 -c '
import json, re, subprocess, sys
min_ver = tuple(int(x) for x in sys.argv[1].split("."))
prefs = sys.argv[2].split("|")
data = json.load(sys.stdin)["devices"]
cands = []
for runtime, devs in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    if ver < min_ver:
        continue
    for d in devs:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            rank = prefs.index(d["name"]) if d["name"] in prefs else len(prefs)
            cands.append((rank, tuple(-v for v in ver), d["name"], d["udid"], "%d.%d" % ver))
if not cands:
    # A runtime without a matching device: create one rather than failing.
    rts = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    rts = [r for r in rts if r.get("isAvailable") and r.get("platform") == "iOS"
           and tuple(int(x) for x in r["version"].split(".")[:2]) >= min_ver]
    if not rts:
        sys.exit(1)
    rt = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
    types = [t for t in rt.get("supportedDeviceTypes", []) if t["name"].startswith("iPhone")]
    if not types:
        sys.exit(1)
    t = next((t for p in prefs for t in types if t["name"] == p), types[-1])
    udid = subprocess.check_output(["xcrun", "simctl", "create", "HH " + t["name"], t["identifier"], rt["identifier"]]).decode().strip()
    print("%s|%s (iOS %s, created)" % (udid, t["name"], rt["version"]))
    sys.exit(0)
cands.sort()
_, _, name, udid, ver = cands[0]
print("%s|%s (iOS %s)" % (udid, name, ver))
' "$MIN_IOS_SDK" "$PREFERRED_DEVICES"
}

destination() { cat "$DEST_FILE"; }

# run_xcodebuild STEP LOGNAME [RESULT_BUNDLE] -- args...
run_xcodebuild() {
    local step="$1" logname="$2" bundle="$3"
    shift 3
    local log="$LOG_DIR/$logname.log"
    local extra=""
    if [ -n "$bundle" ]; then
        rm -rf "$bundle"
        extra="-resultBundlePath $bundle"
    fi
    info "log: ${log#$REPO_ROOT/}"
    set +e
    # shellcheck disable=SC2086
    xcodebuild "$@" -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DERIVED_DATA" $extra \
        >"$log" 2>&1
    local rc=$?
    set -e
    if [ $rc -ne 0 ]; then
        report_xcodebuild_failure "$step" "$log" "$bundle"
        fail "$step" "xcodebuild exited $rc. Diagnostics above; full log at ${log#$REPO_ROOT/}."
    fi
    grep -E "warning: " "$log" | sort -u | head -20 | sed 's/^/    [warn] /' || true
}

report_xcodebuild_failure() {
    local step="$1" log="$2" bundle="$3"
    printf '\n---- %s: compiler/build errors (deduplicated) ----\n' "$step" >&2
    local errors
    errors="$(grep -E "(error|fatal error): " "$log" | sort -u | head -40 || true)"
    if [ -n "$errors" ]; then
        printf '%s\n' "$errors" >&2
        if in_ci; then
            printf '%s\n' "$errors" | python3 -c '
import os, re, sys
ws = os.environ.get("GITHUB_WORKSPACE", "").rstrip("/") + "/"
for line in sys.stdin:
    m = re.match(r"^(/[^:]+):(\d+):(?:(\d+):)? (?:fatal )?error: (.*)$", line.strip())
    if m:
        f, l, c, msg = m.groups()
        f = f[len(ws):] if ws != "/" and f.startswith(ws) else f
        print("::error file=%s,line=%s,col=%s::%s" % (f, l, c or 1, msg))
    else:
        print("::error::" + line.strip()[:400])
'
            summary "### ❌ ${step}" '```' "$errors" '```'
        fi
    fi
    if [ -n "$bundle" ] && [ -d "$bundle" ]; then
        printf '\n---- %s: failing tests ----\n' "$step" >&2
        report_test_failures "$bundle" >&2 || true
    fi
    printf '\n---- %s: last 40 log lines ----\n' "$step" >&2
    tail -n 40 "$log" >&2
}

report_test_failures() {
    local bundle="$1"
    xcrun xcresulttool get test-results summary --path "$bundle" --format json 2>/dev/null | python3 -c '
import json, os, sys
data = json.load(sys.stdin)
fails = data.get("testFailures", [])
print("result=%s passed=%s failed=%s skipped=%s" % (data.get("result"), data.get("passedTests"),
      data.get("failedTests"), data.get("skippedTests")))
lines = []
for f in fails:
    msg = (f.get("failureText") or "").strip().replace("\n", " ")
    line = "%s / %s: %s" % (f.get("targetName"), f.get("testName") or f.get("testIdentifierString"), msg)
    print(line)
    lines.append(line)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("::error title=Test failed: %s::%s" % (f.get("testName"), msg[:400]))
p = os.environ.get("GITHUB_STEP_SUMMARY")
if p and lines:
    with open(p, "a") as fh:
        fh.write("#### Failing tests\n" + "\n".join("- " + l for l in lines) + "\n")
'
}

report_test_counts() {
    local bundle="$1" label="$2"
    local line
    line="$(xcrun xcresulttool get test-results summary --path "$bundle" --format json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("%s: passed=%s failed=%s skipped=%s" % (d.get("result"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests")))
' || echo "summary unavailable")"
    info "$label $line"
    summary "- **$label** $line"
    case "$line" in
        *"passed=0 "*) fail "$label" "0 tests executed; a test target that runs nothing is not a pass." ;;
    esac
}

skip_build() { [ "${HH_SKIP_BUILD:-0}" = "1" ]; }
