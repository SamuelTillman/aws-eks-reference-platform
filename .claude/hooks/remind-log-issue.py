#!/usr/bin/env python3
"""PostToolUse(Bash) reminder: log non-trivial failures in docs/layerN-issues.md.

This repo has a hard rule (CLAUDE.md): every non-trivial deployment/CI issue gets
written up in docs/layer1-issues.md or docs/layer2-issues.md with root cause + fix,
so a forker never has to rediscover it. This hook is a low-noise safety net: when a
Bash command's output carries a failure signature, it injects a one-line reminder
back to Claude. It never blocks and never writes anything itself (the write is a
judgment call). Reminders are advisory only.

Contract: reads the PostToolUse hook JSON on stdin, exits 0 always. When it wants to
remind, it prints a JSON object with hookSpecificOutput.additionalContext.
"""
import json
import re
import sys

# Failure signatures worth a reminder. Kept close to what actually shows up in this
# repo's terraform / aws / gh CI output (see docs/layer[12]-issues.md for the log).
SIGNATURES = [
    r"\bError:",                       # terraform / generic tool error prefix
    r'"conclusion"\s*:\s*"failure"',   # gh run / API JSON for a failed CI job
    r"Invalid\w*\.NotFound",           # AWS eventual-consistency races (TGW, ENI, ...)
    r"exited with code [1-9]",         # non-zero exit reported in output
    r"Terraform exited with code",     # setup-terraform / CI wrapper failure line
    r"does not exist",                 # deleted/absent resource (races, wrong ID)
    r"AccessDenied",                   # IAM / OIDC / delegated-admin permission gap
]
SIGNATURE_RE = re.compile("|".join(SIGNATURES))

# Commands that merely READ or SEARCH text would match the signatures on their own
# content (Claude grepping the codebase, catting the issues log, etc.). Skip those so
# the reminder only fires on commands that DO something and fail.
BENIGN_CMD_RE = re.compile(
    r"^\s*(sudo\s+)?"
    r"(grep|rg|ag|ack|cat|bat|less|more|head|tail|echo|printf|awk|sed|"
    r"find|fd|ls|tree|jq|yq|diff|git\s+(diff|log|show|grep|blame))\b"
)

# Never remind on the hook's own test/setup traffic.
SELF_REF_RE = re.compile(r"claude-hook-check|remind-log-issue")


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # never break the tool flow on a parse hiccup

    if event.get("tool_name") != "Bash":
        return 0

    command = (event.get("tool_input") or {}).get("command", "") or ""
    if BENIGN_CMD_RE.search(command) or SELF_REF_RE.search(command):
        return 0

    # tool_response may be a string or an object (stdout/stderr/etc). Search it whole.
    response = event.get("tool_response", "")
    haystack = response if isinstance(response, str) else json.dumps(response)
    if SELF_REF_RE.search(haystack):
        return 0

    if not SIGNATURE_RE.search(haystack):
        return 0

    # Which log? Layer 2 covers eks/argocd/cluster work; everything else is Layer 1.
    scope = command + " " + haystack
    if re.search(r"\b(eks|argocd|kubectl|helm|cluster|karpenter|layer2)\b", scope, re.I):
        target = "docs/layer2-issues.md"
    else:
        target = "docs/layer1-issues.md"

    reminder = (
        f"A failure signature appeared in that command's output. Per this repo's hard "
        f"rule (CLAUDE.md), if this is a non-trivial deployment/CI issue, log it in "
        f"{target} with symptom, root cause, fix, and prevention once it's understood. "
        f"If it's transient/benign (e.g. an eventual-consistency race cleared by a "
        f"re-run) or already logged, no new entry is needed."
    )
    print(json.dumps({
        "suppressOutput": True,
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": reminder,
        },
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
