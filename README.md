# Agent Guardrails

An enforcement and safety layer for AI-assisted development at the BC Government. This repository installs local hooks and shell wrappers to prevent common AI accidents, secure repositories, and maintain compliant development workflows.

---

## What Are These Guardrails?

These guardrails consist of a local security system that wraps critical commands and implements global git hooks:

1.  **Secret Scanner (gitleaks)** - Scans all commits locally for API keys, credentials, and secrets before they can be committed.
2.  **Global Git Hooks (pre-commit and pre-push)** - Intercepts git actions:
    *   `pre-commit`: Runs `gitleaks` and blocks version regressions.
    *   `pre-push`: Prevents direct pushes to protected branches like `main` or `master`.
3.  **Shell Safety Wrappers (git-safety.sh)** - Sourced in the shell (`~/.bashrc`) to intercept commands executed by development agents or humans, blocking unsafe actions.

---

## Why Were They Selected?

AI agents (such as GitHub Copilot Workspace or agentic coders) run within local development environments. While powerful, they can introduce specific risks:

*   **Accidental Secret Exposure** - Agents often generate mock keys or accidentally commit raw environment variables. Pre-commit `gitleaks` intercepts these before they hit git history.
*   **Bypassing Repository Safety** - When a test or hook fails, an agent's default instinct is often to bypass it using `--no-verify`. The shell wrappers actively block this bypass.
*   **Altering Environment State** - Agents sometimes modify global Git configs or shell profiles to force execution. Wrapping `git config` keeps changes isolated and explicit.
*   **Direct Push Failures** - Agents may attempt to push code directly to `main` to speed up tasks. The `pre-push` hook enforces feature branch workflows.

---

## What Is Blocked?

The safety wrappers intercept commands and block specific actions and arguments based on repository policy:

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

---

## How Do the Safety Wrappers Run?

Sourcing shell profiles behaves differently depending on how a command session is initialized:

### Interactive Shell Loading
When you start a terminal session, your interactive shell reads and executes `~/.bashrc`. The installer appends a loader block to your `~/.bashrc` which sources `git-safety.sh`. This defines shell functions (`git`, `gh`, `npm`, `npx`) that intercept execution.

### Non-Interactive Shell Loading (AI Agent Coverage)
Many AI coding agents execute commands within non-interactive sub-shells. Bash does not load `~/.bashrc` for non-interactive shells, which normally means safety functions would be bypassed and lost.

To guarantee coverage, our loader block in `~/.bashrc` exports the `BASH_ENV` environment variable:

```bash
export BASH_ENV="$HOME/.githooks/git-safety.sh"
```

When a non-interactive Bash sub-shell is initialized (such as when an AI agent runs shell commands), Bash automatically checks the `BASH_ENV` variable and sources the file it points to before executing any script or command. This ensures the safety wrappers remain active and cannot be avoided by running tasks in the background.

---

## How Are They Arranged?

The repository is structured logically around the setup automation and the assets it deploys:

*   [setup.sh](file:///home/derek/Repos/agent-guardrails/setup.sh) - The main installer script. It detects the OS, downloads the correct `gitleaks` binary, copies hooks and wrappers, and updates shell configuration files.
*   [scripts/hooks/](file:///home/derek/Repos/agent-guardrails/scripts/hooks) - Templates for global git hooks:
    *   `pre-commit`: Triggers local `gitleaks` scanning.
    *   `pre-push`: Validates the destination branch.
*   [scripts/git-safety.sh](file:///home/derek/Repos/agent-guardrails/scripts/git-safety.sh) - Contains the safety shell functions that wrap `git`, `gh`, `npm`, and `npx` to check arguments for unsafe patterns.
*   [scripts/git-setup.sh](file:///home/derek/Repos/agent-guardrails/scripts/git-setup.sh) - An optional, interactive script to establish robust baseline git settings for human developers (e.g., conflict resolution, diff coloring).

---

## How to Install Them

### Standard One-Liner (Recommended)
You can install the guardrails directly without cloning the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash
```

### Local Installation
Alternatively, clone the repository and run the setup script locally:

```bash
git clone https://github.com/bcgov/agent-guardrails.git
cd agent-guardrails && ./setup.sh
```

> [!NOTE]
> After installation, you must restart your terminal or run `source ~/.bashrc` to load the safety wrappers.

### Optional: Interactive Git Config
To configure human-friendly Git default settings, run:

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/scripts/git-setup.sh | bash
```

---

## What is not in this repo

*   **Shared Copilot Guidelines** - [bcgov/copilot-instructions](https://github.com/bcgov/copilot-instructions) contains the shared behavioural guidelines.
*   **Agent Skills** - [bcgov/agent-skills](https://github.com/bcgov/agent-skills) is a community catalogue of reusable agent skill profiles.
