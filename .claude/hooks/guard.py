#!/usr/bin/env python3
"""PreToolUse guard: returns permissionDecision "ask" for the require-confirmation list in CLAUDE.md / spec §15.8.

Silent (exit 0, no output) when the call is not on the list. Never blocks outright; the owner decides.
"""
import json
import pathlib
import re
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def ask(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"Household Hub guard: {reason}",
        }
    }))
    sys.exit(0)


# ---------- Bash ----------

GIT_RULES = [
    (r"\bpush\b.*(\s--force\b|\s-f\b|\s--force-with-lease\b|\s--force-if-includes\b|\s\+\S)", "force push"),
    (r"\bpush\b.*(\s--delete\b|\s-d\b|\s:\S)", "deleting a remote branch/tag"),
    (r"\breset\b.*--hard\b", "git reset --hard discards work"),
    (r"\bclean\b.*\s-[a-zA-Z]*f", "git clean deletes untracked files"),
    (r"\bcheckout\b.*\s(--\s|\.\s*$|\.\s)", "git checkout discarding working-tree changes"),
    (r"\brestore\b", "git restore discards changes"),
    (r"\bbranch\b.*\s-(D|d|-delete)\b", "deleting a branch"),
    (r"\brebase\b", "rebase rewrites history"),
    (r"\bcommit\b.*--amend\b", "amending rewrites history"),
    (r"\b(filter-branch|filter-repo|replace)\b", "history rewrite"),
    (r"\btag\b.*\s-d\b", "deleting a tag"),
    (r"\bupdate-ref\b.*\s-d\b", "deleting a ref"),
    (r"\bstash\b.*\b(drop|clear)\b", "dropping stashed work"),
    (r"\breflog\b.*\bexpire\b|\bgc\b.*--prune", "pruning recoverable history"),
    (r"\bpush\b.*(\smain\b|:main\b|:refs/heads/main\b)", "pushing to main"),
]

CMD_RULES = [
    (r"\bgh\s+pr\s+merge\b", "merging a PR (merge to main needs explicit go-ahead)"),
    (r"\bgh\s+repo\s+edit\b.*--visibility", "changing repository visibility"),
    (r"\bgh\s+api\b.*(visibility|\"private\"|private=)", "changing repository visibility via API"),
    (r"\bgh\s+(repo\s+delete|release\s+delete)\b", "deleting GitHub resources"),
    (r"\bxcrun\s+simctl\s+(erase|delete|uninstall)\b", "deleting simulator data (persisted user data)"),
    (r"\b(brew|pip3?|pipx|gem|mint|pod)\s+install\b", "installing a third-party tool/package"),
    (r"\bnpm\s+(install|i|add)\b|\byarn\s+add\b|\bpnpm\s+add\b", "installing a third-party package"),
    (r"\bswift\s+package\s+(add-dependency|add-target-dependency)\b", "adding a Swift package dependency"),
    (r"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b", "piping a remote script into a shell"),
    (r"\bclaude\s+mcp\s+(add|remove|add-json)\b", "modifying MCP configuration/credentials"),
    (r"\bsecurity\s+(add|delete|import|set)-|\bcodesign\b", "changing signing identities/keychain"),
    (r"\bsudo\b", "sudo"),
]

SAFE_RM_PREFIXES = ("build/", "./build/", "/tmp/", "DerivedData/", "HouseholdHub.xcodeproj")


def current_branch():
    try:
        return subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--abbrev-ref", "HEAD"],
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def check_rm(segment):
    try:
        toks = shlex.split(segment)
    except ValueError:
        return "rm with unparseable arguments"
    for i, t in enumerate(toks):
        if t in ("rm", "unlink", "rmdir") or t.endswith("/rm"):
            targets = [a for a in toks[i + 1:] if not a.startswith("-")]
            bad = [a for a in targets if not a.startswith(SAFE_RM_PREFIXES) and "claude-0/" not in a]
            if bad:
                return f"deleting files ({', '.join(bad[:3])})"
    if re.search(r"\bfind\b.*\s-delete\b", segment):
        return "find -delete removes files"
    return None


def check_bash(cmd):
    segments = re.split(r"&&|\|\||;|\n", cmd)
    for seg in segments:
        s = seg.strip()
        if not s:
            continue
        if re.search(r"(^|\s)(rm|unlink|rmdir)\s|\bfind\b.*-delete", s):
            r = check_rm(s)
            if r:
                return r
        if re.search(r"(^|\s)git(\s+-C\s+\S+)?\s", s):
            for pat, reason in GIT_RULES:
                if re.search(pat, s):
                    return reason
            if re.search(r"\bgit(\s+-C\s+\S+)?\s+rm\b", s):
                return "git rm deletes project files"
            if re.search(r"\bgit(\s+-C\s+\S+)?\s+merge\b", s) and current_branch() == "main":
                return "merging into main"
        for pat, reason in CMD_RULES:
            if re.search(pat, s):
                return reason
    return None


# ---------- file edits ----------

def old_and_new(tool, inp):
    path = pathlib.Path(inp.get("file_path") or inp.get("notebook_path") or "")
    if not path.is_absolute():
        path = ROOT / path
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if tool == "Write":
        new = inp.get("content", "")
    elif tool == "Edit":
        o, n = inp.get("old_string", ""), inp.get("new_string", "")
        new = old.replace(o, n) if inp.get("replace_all") else old.replace(o, n, 1)
    else:
        new = old + "\n<notebook edit>"
    return path, old, new


def yaml_blocks(text, key):
    """Return every `key:` block (the key line plus its more-indented body) as normalized text."""
    lines, out, i = text.splitlines(), [], 0
    while i < len(lines):
        m = re.match(rf"^(\s*)['\"]?{key}['\"]?\s*:(.*)$", lines[i])
        if m:
            indent, block = len(m.group(1)), [lines[i].strip()]
            i += 1
            while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
                if lines[i].strip() and not lines[i].strip().startswith("#"):
                    block.append(lines[i].strip())
                i += 1
            out.append("\n".join(block))
        else:
            i += 1
    return out


def key_lines(text, pattern):
    return sorted(l.strip() for l in text.splitlines() if re.search(pattern, l))


def check_edit(tool, inp):
    path, old, new = old_and_new(tool, inp)
    try:
        rel = str(path.resolve().relative_to(ROOT))
    except ValueError:
        return None
    name = path.name

    if rel.startswith(".github/workflows/"):
        for key in ("on", "permissions"):
            if yaml_blocks(old, key) != yaml_blocks(new, key):
                return f"changing the workflow's `{key}:` (trigger/permissions scope) in {rel}"
        if not path.exists():
            return f"adding a new workflow {rel}"
    if name == ".mcp.json":
        return "modifying .mcp.json (MCP configuration/credentials)"
    if rel.startswith(".claude/hooks/") or rel in (".claude/settings.json",):
        return f"modifying the guardrails themselves ({rel})"
    if name.endswith(".entitlements"):
        return f"changing entitlements ({rel})"
    if "oauth" in name.lower() or name == "GoogleService-Info.plist":
        return f"changing external OAuth configuration ({rel})"
    sign = r"DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE|CODE_SIGN_ENTITLEMENTS"
    if key_lines(old, sign) != key_lines(new, sign):
        return f"changing signing settings in {rel}"
    oauth = r"CFBundleURLSchemes|GIDClientID|client_id|clientID"
    if key_lines(old, oauth) != key_lines(new, oauth):
        return f"changing OAuth/URL-scheme configuration in {rel}"
    if name == "project.yml" and yaml_blocks(old, "packages") != yaml_blocks(new, "packages"):
        return "adding/changing Swift package dependencies in project.yml"
    if name == "Package.swift" and key_lines(old, r"\.package\(") != key_lines(new, r"\.package\("):
        return "adding/changing Swift package dependencies in Package.swift"
    return None


# ---------- MCP ----------

def check_mcp(tool, inp):
    short = tool.split("__")[-1]
    if short in ("merge_pull_request", "enable_pr_auto_merge"):
        return "merging a PR (merge to main needs explicit go-ahead)"
    if short == "delete_file":
        return "deleting a file via the GitHub API"
    if short in ("create_or_update_file", "push_files") and inp.get("branch") == "main":
        return "writing directly to main via the GitHub API"
    if short == "create_repository" or short == "fork_repository":
        return "creating a repository"
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    tool, inp = data.get("tool_name", ""), data.get("tool_input") or {}
    reason = None
    if tool == "Bash":
        reason = check_bash(inp.get("command", ""))
    elif tool in ("Edit", "Write", "NotebookEdit"):
        reason = check_edit(tool, inp)
    elif tool.startswith("mcp__"):
        reason = check_mcp(tool, inp)
    if reason:
        ask(reason)


if __name__ == "__main__":
    main()
