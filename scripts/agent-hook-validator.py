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
                    if t in ("--tags", "-f", "--force"):
                        return True, "AI Agents cannot manage tags or force push."
                        
            elif subcmd in ("rebase", "merge"):
                for t in tokens[subcmd_idx+1:]:
                    if t in ("-i", "--interactive", "squash", "fixup", "--autosquash", "--squash"):
                        return True, "Squashing commits and interactive rebasing are forbidden."

    # 3. gh operations
    if cmd == "gh":
        # Find subcommand
        subcmd = None
        subcmd_idx = -1
        for i, t in enumerate(tokens[1:]):
            if not t.startswith('-'):
                subcmd = t.lower()
                subcmd_idx = i + 1
                break
        
        if subcmd == "release":
            return True, "Managing GitHub Releases is forbidden."
        elif subcmd == "secret":
            return True, "Managing repository secrets is forbidden."
            
        # Check compound commands like 'repo delete' or 'pr merge'
        if subcmd_idx != -1 and subcmd_idx + 1 < len(tokens):
            subsubcmd = tokens[subcmd_idx+1].lower()
            if subcmd == "repo" and subsubcmd == "delete":
                return True, "Repository deletion is strictly forbidden."
            if subcmd in ("issue", "pr") and subsubcmd in ("comment", "review", "merge"):
                return True, "Impersonating humans in PRs/Issues or merging PRs is forbidden."

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
