#!/usr/bin/env python3
import sys
import json
import re

import shlex

def is_blocked(cmd_string):
    """
    Evaluates a command string against agent-guardrails policies.
    Returns (True, reason) if blocked, or (False, "") if allowed.
    """
    try:
        tokens = shlex.split(cmd_string)
    except ValueError:
        # Malformed quotes, fallback to simple string matching
        tokens = cmd_string.split()
    
    if not tokens:
        return False, ""
    
    cmd = tokens[0].lower()
    
    # 1. oc / kubectl
    if cmd in ("oc", "kubectl"):
        return True, "Access to Kubernetes/OpenShift clusters is restricted for autonomous agents."

    # 2. git operations
    if cmd == "git":
        # Find the subcommand (first token that doesn't start with '-')
        subcmd = None
        subcmd_idx = -1
        for i, t in enumerate(tokens[1:]):
            if not t.startswith('-'):
                subcmd = t.lower()
                subcmd_idx = i + 1
                break
                
        if subcmd:
            if subcmd == "commit":
                # Check for --no-verify or combined -n (e.g., -an, -nm)
                for t in tokens[subcmd_idx+1:]:
                    if t == "--no-verify" or (t.startswith('-') and not t.startswith('--') and 'n' in t):
                        return True, "AI Agents are STRICTLY FORBIDDEN from bypassing Git hooks (--no-verify)."
            
            elif subcmd == "config":
                return True, "Modifying Git configuration is forbidden for AI agents."
                
            elif subcmd == "tag":
                return True, "AI Agents cannot manage tags or force push."
                
            elif subcmd == "push":
                for t in tokens[subcmd_idx+1:]:
                    if t in ("--tags", "-f", "--force") or t.startswith("--force-with-lease"):
                        return True, "AI Agents cannot manage tags or force push."
                        
            elif subcmd in ("rebase", "merge"):
                for t in tokens[subcmd_idx+1:]:
                    if t in ("-i", "--interactive", "squash", "fixup", "--autosquash", "--squash"):
                        return True, "Squashing commits and interactive rebasing are forbidden."

    # 3. gh operations
    if cmd == "gh":
        # Extract positional non-option tokens
        positional = []
        for t in tokens[1:]:
            if not t.startswith('-'):
                positional.append(t.lower())

        subcmd = positional[0] if positional else ""
        subsubcmd = positional[1] if len(positional) > 1 else ""

        if subcmd == "release":
            return True, "Managing GitHub Releases is forbidden."
        elif subcmd == "secret":
            return True, "Managing repository secrets is forbidden."
        elif subcmd == "repo" and subsubcmd == "delete":
            return True, "Deleting repositories is forbidden."

        if subcmd in ("issue", "pr"):
            if subsubcmd in ("comment", "review"):
                return True, "Impersonating humans in PRs/Issues is strictly forbidden."
            if subcmd == "pr" and subsubcmd in ("merge", "close"):
                return True, "Merging or closing PRs is strictly forbidden."

            # Check for --comment / -c flag on ANY pr/issue command (e.g., gh pr close --comment "...")
            for t in tokens:
                if t in ("-c", "--comment"):
                    return True, "Posting PR/Issue comments (including via --comment/-c flag) impersonates human developers and is strictly forbidden."

        if subcmd == "api":
            # Inspect HTTP method and flags
            method = "GET"
            fields = []
            for idx, t in enumerate(tokens):
                if t in ("-X", "--method") and idx + 1 < len(tokens):
                    method = tokens[idx + 1].upper()
                elif t in ("-f", "-F", "--raw-field", "--field", "--input"):
                    if method == "GET":
                        method = "POST"
                    if idx + 1 < len(tokens):
                        fields.append(tokens[idx + 1])

            if method in ("POST", "PATCH", "PUT", "DELETE"):
                joined = " ".join(tokens)
                for t in tokens:
                    if "/comments" in t or "/reviews" in t:
                        return True, "Creating or updating comments/reviews via GitHub API impersonates human developers and is strictly forbidden."
                # Close PR/issue via REST: PATCH .../pulls|issues/N with state=closed
                if re.search(r"/pulls/\d+", joined) or re.search(r"/issues/\d+", joined):
                    for f in fields:
                        if f.lower() in ("state=closed", "state:closed") or f.lower().startswith("state=closed"):
                            return True, "Closing PRs/issues via GitHub API is strictly forbidden."
                    if "state=closed" in joined.lower() or '"state":"closed"' in joined.lower().replace(" ", ""):
                        return True, "Closing PRs/issues via GitHub API is strictly forbidden."

    # 4. npm / npx operations
    if cmd in ("npm", "npx"):
        if "--legacy-peer-deps" in tokens:
            return True, "Bypassing peer dependencies with --legacy-peer-deps is forbidden. Resolve conflicts cleanly."

    return False, ""

def main():
    try:
        input_data = sys.stdin.read().strip()
        if not input_data:
            # If no stdin, allow by default (fail-open for humans)
            sys.exit(0)
            
        payload = json.loads(input_data)
    except json.JSONDecodeError:
        # If invalid JSON, fail-open to allow the tool to continue
        # (Though we might want to fail-closed, failing open prevents breaking non-JSON uses)
        sys.exit(0)

    # Detect the agent/schema type
    hook_event = payload.get("hook_event_name", "")
    
    # Extract the command based on the schema
    command_to_evaluate = ""
    is_claude = False
    is_cursor = False
    
    if hook_event == "PreToolUse" or payload.get("hookEventName") == "PreToolUse" or "tool_input" in payload:
        is_claude = True
        # Claude Code schema
        tool_input = payload.get("tool_input", {})
        command_to_evaluate = tool_input.get("command", "")
    elif hook_event == "beforeShellExecution" or "cursor_version" in payload:
        is_cursor = True
        # Cursor schema (command is usually passed in the payload or we inspect the raw string)
        # We try to find the command field if it exists.
        command_to_evaluate = payload.get("command", "")
        # If the schema wraps it differently, we can fallback to dumping the payload and regexing
        if not command_to_evaluate:
            command_to_evaluate = json.dumps(payload)
    else:
        # Unknown schema, try to find a 'command' key
        command_to_evaluate = payload.get("command", json.dumps(payload))

    if not command_to_evaluate:
        sys.exit(0)

    blocked, reason = is_blocked(command_to_evaluate)

    if not blocked:
        # If allowed, we can just return standard allow JSON depending on the platform,
        # or just exit 0 which most platforms interpret as 'allow'.
        if is_claude:
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow"
                }
            }))
        elif is_cursor:
            print(json.dumps({
                "permission": "allow"
            }))
        sys.exit(0)

    # If blocked:
    if is_claude:
        # Claude uses a structured deny
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"AGENT-GUARDRAILS BLOCKED: {reason}"
            }
        }))
        sys.exit(2) # Claude Code uses exit code 2 as a hard block sometimes, but JSON works too
        
    elif is_cursor:
        # Cursor uses permission: deny
        print(json.dumps({
            "permission": "deny",
            "agentMessage": f"AGENT-GUARDRAILS BLOCKED: {reason}"
        }))
        sys.exit(2)
        
    else:
        # Generic block for unknown tools
        print(json.dumps({
            "permission": "deny",
            "error": reason
        }))
        sys.stderr.write(f"BLOCKED: {reason}\n")
        sys.exit(2)

if __name__ == "__main__":
    main()
