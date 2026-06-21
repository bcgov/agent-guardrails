# Agent Guardrails

An enforcement and safety layer for AI-assisted development at the BC Government. This repository installs local git hooks and shell safety wrappers to prevent common AI accidents, secure repositories, and maintain compliant development workflows.

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
Legitimate overrides can be performed by prefixing commands with the `command` keyword:
```bash
command git config --local user.email "your.email@gov.bc.ca"
```

---

## What Is Blocked?

The safety wrappers intercept commands and block specific actions based on repository policy:

| Tool | Blocked Action / Argument | Reason for Policy |
| :--- | :--- | :--- |
| **git** | `commit --no-verify`, `commit -n` | Prevents agents from bypassing commit hooks. |
| **git** | `config` subcommand | Prevents modifications to global configurations. |
| **git** | `tag` subcommand, `push --tags` | Restricts automated release/tag creation. |
| **git** | `rebase -i`, `--interactive`, `squash`, `fixup`, `--autosquash` | Avoids squashing or history rewrite in branch history. |
| **git** | `merge --squash` | Blocks squashing commits during PR merge. |
| **gh** | `release` | Blocks automated release management. |
| **gh** | `repo delete` | Prevents destructive repository deletions. |
| **gh** | `secret` | Restricts automated credential/secret modifications. |
| **gh** | `issue comment`, `pr comment`, `pr review` | Prevents impersonation of human developers in discussions. |
| **gh** | `pr merge` | Forces PR merges to be performed manually by a human reviewer. |
| **npm / npx** | `--legacy-peer-deps` | Prevents dirty dependency resolution bypasses. |
| **npm / npx** | `NPM_CONFIG_LEGACY_PEER_DEPS` environment variable | Blocks env-level peer dependency bypasses. |
| **kubectl** | All commands | Prevents automated cluster management and unauthorized access to environments. |
| **oc** | All commands | Prevents automated OpenShift management and unauthorized access to environments. |

---

## How It Works

### Non-Interactive Shell Loading (AI Agent Coverage)
Many AI coding agents execute commands within non-interactive sub-shells. Because Bash does not load `~/.bashrc` for non-interactive shells, the installer exports the `BASH_ENV` environment variable:

```bash
export BASH_ENV="$HOME/.githooks/git-safety.sh"
```

When a non-interactive Bash sub-shell is initialized, Bash automatically checks `BASH_ENV` and sources the file it points to before executing any script or command. This ensures safety wrappers remain active during background agent runs.

### Security Model and Limitations
These guardrails serve as a safety net and a gentle nudge for helpful, well-intentioned AI agents. They do not constitute a security boundary or a bulletproof cage against malicious code. Bad-faith agents can easily override shell functions or delete local hooks. Real security must be enforced at the server/repository level (such as branch protection rules and CI pipelines).

---

## What is not in this repo

*   **Shared Copilot Guidelines** - [bcgov/copilot-instructions](https://github.com/bcgov/copilot-instructions) contains the shared behavioural guidelines.
*   **Agent Skills** - [bcgov/agent-skills](https://github.com/bcgov/agent-skills) is a community catalogue of reusable agent skill profiles.
