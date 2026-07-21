# Agent Guardrails

AI-assisted development accelerates velocity, but autonomous agents require guardrails to protect shared environments and maintain compliance.

This repository establishes a client-side safety net that intercepts standard command paths to enforce a **human-in-the-loop** workflow:

*   **Infrastructure Safeguards**: Intercepts standard `oc` and `kubectl` execution to prevent AI agents from accidentally modifying or querying live Kubernetes/OpenShift environments.
*   **Enforced Repository Standards**: Intercepts shortcut flags (like `commit --no-verify` or `--legacy-peer-deps`) to ensure AI-generated code passes the exact same linting, testing, and dependency checks as human code.
*   **Accountability & Attribution**: Intercepts automated Pull Request merges, secret management, and release publishing via the GitHub CLI (`gh`), preserving human review as the final gate.

This is a safety belt, not a sandbox. It won't stop a malicious agent, but it prevents well-intentioned tools from making automated mistakes.

---

## Installation

Run the one-liner setup script (requires `bash` and `curl`):

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
```

Alternatively, clone the repository and run the setup script locally:

```bash
git clone https://github.com/bcgov/agent-guardrails.git
cd agent-guardrails && ./setup.sh
```

After installation, restart your terminal or run `source ~/.bashrc` to load the safety wrappers.

### Verification
Confirm the wrappers are active by checking that git is defined as a function:
```bash
type git
```
Running a blocked command (like `git config`) should trigger a blocked error message.

### Bypassing (For Human Developers)
Human developers running commands in interactive shell sessions bypass all safety wrapper checks automatically without any extra steps. If you ever need to bypass wrappers in a non-interactive script or piped command, prefix the command with `command`:
```bash
command git commit -m "feat: manual release" --no-verify
```

---

## What Is Blocked?

The safety wrappers intercept commands and block specific actions for AI agents based on repository policy:

| Tool | Blocked Action / Argument | Reason for Policy |
| :--- | :--- | :--- |
| **oc / kubectl** | All commands | Prevents automated cluster management and unauthorized access to environments. |
| **git** | `commit --no-verify`, `commit -n` | Prevents agents from bypassing commit hooks. |
| **git** | `config` subcommand | Prevents modifications to global configurations. |
| **git** | `tag` subcommand, `push --tags` | Restricts automated release/tag creation. |
| **git** | `rebase -i`, `--interactive`, `squash`, `fixup`, `--autosquash` | Avoids squashing or history rewrite in branch history. |
| **git** | `merge --squash`, `commit --amend`, `push --force` | Blocks squashing, amending, and force-pushing remote history. |
| **gh** | `release` | Blocks automated release management. |
| **gh** | `repo delete` | Prevents destructive repository deletions. |
| **gh** | `secret` | Restricts automated credential/secret modifications. |
| **gh** | `issue comment`, `pr comment`, `pr review` | Prevents impersonation of human developers in discussions. |
| **gh** | `pr merge` | Forces PR merges to be performed manually by a human reviewer. |
| **npm / npx** | `--legacy-peer-deps` | Prevents dirty dependency resolution bypasses. |
| **npm / npx** | `NPM_CONFIG_LEGACY_PEER_DEPS` environment variable | Blocks env-level peer dependency bypasses. |

---

## How It Works

### The Hybrid Architecture: Native Hooks + Shell Fallbacks
Because there are many different types of AI agents, this repository uses a **hybrid architecture** (defense-in-depth) to enforce guardrails:

1. **Agent-Native Hooks (Application Layer)**: Modern IDEs like Cursor and Claude Code provide native pre-execution hooks (e.g., `.cursor/hooks.json` or `.claude/settings.json`). The installer automatically injects a lightning-fast, Python-based validator script into these configurations. This ensures dangerous commands are intercepted natively *before* a sub-shell is even spawned.
2. **Shell Wrappers (Shell Layer)**: CLI agents (like Aider, Cline, or Antigravity) do not have native hook frameworks. They execute raw commands in background terminal sessions. To catch these, the installer configures `BASH_ENV` to load safety wrapper functions (e.g., `git()` and `oc()`) in all bash sub-shells. 

This two-tier approach guarantees un-bypassable protection for supported IDEs, while maintaining a universal safety net for background agent tasks.

### Non-Interactive Shell Loading (AI Agent Coverage)
Many AI coding agents execute commands within non-interactive sub-shells. Because Bash does not load `~/.bashrc` for non-interactive shells, the installer exports the `BASH_ENV` environment variable:

```bash
export BASH_ENV="$HOME/.githooks/git-safety.sh"
```

When a non-interactive Bash sub-shell is initialized, Bash automatically checks `BASH_ENV` and sources the file it points to before executing any script or command. This ensures safety wrappers remain active during background agent runs.

### AI Agent Detection (Interactive vs. Non-Interactive)
All safety wrapper commands (`git`, `gh`, `npm`, `npx`, `oc`, `kubectl`) use an `_is_ai_agent()` check. Human developers running commands in normal interactive shells are untouched.

The script identifies AI environments based on:
1. **Agent Markers**: The presence of environment variables injected by agent platforms (e.g., `ANTIGRAVITY_AGENT`, `AIDER_YT_VIDEO`, `CLINE_API_KEY`, `RM_CLINE`, etc.).
2. **Non-Interactive Execution**: Whether the shell is non-interactive (`$- != *i*`).
3. **Terminal Type & Pipe**: Whether `TERM` is set to `dumb` or standard output is not attached to a terminal (`! [[ -t 1 ]]`).

### Security Model and Limitations
These guardrails serve as a safety net and a gentle nudge for helpful, well-intentioned AI agents. They do not constitute a security boundary or a bulletproof cage against malicious code. Bad-faith agents can easily override shell functions or delete local hooks. Real security must be enforced at the server/repository level (such as branch protection rules and CI pipelines).

---

## What is not in this repo

*   **Shared Agent Guidelines** - [bcgov/agent-instructions](https://github.com/bcgov/agent-instructions) contains the shared behavioural guidelines.
*   **Agent Skills** - [bcgov/agent-skills](https://github.com/bcgov/agent-skills) is a community catalogue of reusable agent skill profiles.
