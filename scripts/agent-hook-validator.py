#!/usr/bin/env python3
import sys
import json
import re

def is_blocked(cmd_string):
    """
    Evaluates a command string against agent-guardrails policies.
    Returns (True, reason) if blocked, or (False, "") if allowed.
    """
    # Split the command cleanly, respecting quotes would be ideal, but for basic
    # guardrails, simple string/regex matching on the raw command is often safer
    # and catches bypasses like `git  commit   --no-verify`.
    cmd_lower = cmd_string.lower()

    # 1. oc / kubectl
    if re.search(r'\b(oc|kubectl)\b', cmd_lower):
        return True, "Access to Kubernetes/OpenShift clusters is restricted for autonomous agents."

    # 2. git operations
    if re.search(r'\bgit\b', cmd_lower):
        if re.search(r'\bcommit\b', cmd_lower) and re.search(r'(--no-verify|-n\b)', cmd_lower):
            return True, "AI Agents are STRICTLY FORBIDDEN from bypassing Git hooks (--no-verify)."
        if re.search(r'\bconfig\b', cmd_lower):
            return True, "Modifying Git configuration is forbidden for AI agents."
        if re.search(r'\btag\b', cmd_lower) or re.search(r'\bpush\b.*(--tags|-f\b|--force\b)', cmd_lower):
            return True, "AI Agents cannot manage tags or force push."
        if re.search(r'\brebase\b.*(-i\b|--interactive|squash|fixup|--autosquash)', cmd_lower) or \
           re.search(r'\bmerge\b.*(--squash|squash)', cmd_lower):
            return True, "Squashing commits and interactive rebasing are forbidden."

    # 3. gh operations
    if re.search(r'\bgh\b', cmd_lower):
        if re.search(r'\brelease\b', cmd_lower):
            return True, "Managing GitHub Releases is forbidden."
        if re.search(r'\brepo\s+delete\b', cmd_lower):
            return True, "Repository deletion is strictly forbidden."
        if re.search(r'\bsecret\b', cmd_lower):
            return True, "Managing repository secrets is forbidden."
        if re.search(r'\b(issue|pr)\s+(comment|review|merge)\b', cmd_lower):
            return True, "Impersonating humans in PRs/Issues or merging PRs is forbidden."

    # 4. npm / npx operations
    if re.search(r'\b(npm|npx)\b', cmd_lower) and '--legacy-peer-deps' in cmd_lower:
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
