# Agent Guardrails

An enforcement and safety layer for AI-assisted development at the BC Government. This repository installs local hooks and shell wrappers to prevent common AI accidents, secure repositories, and maintain compliant development workflows.

---

## What Are These Guardrails?

These guardrails consist of a local security system that wraps critical commands and implements global git hooks:

1.  **Secret Scanner (gitleaks)** - Scans all commits locally for API keys, credentials, and secrets before they can be committed.
2.  **Global Git Hooks (pre-commit and pre-push)** - Intercepts git actions:
    *   `pre-commit`: Runs `gitleaks` and blocks version regressions.
    *   `pre-push`: Prevents direct pushes to protected branches like `main` or `master`.
3.  **Shell Safety Wrappers (git-safety.sh)** - Sourced in the shell (`~/.bashrc`) to intercept commands executed by development agents or humans, blocking unsafe actions:
    *   Prevents bypassing hooks (e.g., `git commit --no-verify`).
    *   Blocks altering global git configuration (e.g., `git config --global`).
    *   Blocks direct command-line pull request merges (e.g., `gh pr merge`).

---

## Why Were They Selected?

AI agents (such as GitHub Copilot Workspace or agentic coders) run within local development environments. While powerful, they can introduce specific risks:

*   **Accidental Secret Exposure** - Agents often generate mock keys or accidentally commit raw environment variables. Pre-commit `gitleaks` intercepts these before they hit git history.
*   **Bypassing Repository Safety** - When a test or hook fails, an agent's default instinct is often to bypass it using `--no-verify`. The shell wrappers actively block this bypass.
*   **Altering Environment State** - Agents sometimes modify global Git configs or shell profiles to force execution. Wrapping `git config` keeps changes isolated and explicit.
*   **Direct Push Failures** - Agents may attempt to push code directly to `main` to speed up tasks. The `pre-push` hook enforces feature branch workflows.

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
