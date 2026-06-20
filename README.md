# Agent Guardrails

Enforcement layer for AI-assisted development at BC Government: shell safety wrappers, global git hooks, and optional human git configuration.

This repo is **operational guardrails only** — not instruction text. Behavioural standards live in [bcgov/copilot-instructions](https://github.com/bcgov/copilot-instructions).

## Quick install

```bash
# One-liner (curl mode — fetches latest main)
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/setup.sh | bash

# Or clone and run locally
git clone https://github.com/bcgov/agent-guardrails.git
cd agent-guardrails && ./setup.sh
```

## What gets installed

| Component | Destination | Purpose |
|-----------|-------------|---------|
| Gitleaks | `~/.local/bin/gitleaks` | Secret scanning on commit |
| Global hooks | `~/.githooks/` | pre-commit (gitleaks + version regression), pre-push (block main/master) |
| Shell safety | `~/.githooks/git-safety.sh` + `~/.bashrc` loader | Blocks `git config`, `--no-verify`, `gh pr merge`, etc. |

Restart your terminal or run `source ~/.bashrc` after install.

## Optional: Git configuration

Human git defaults (interactive — not AI instructions):

```bash
curl -fsSL https://raw.githubusercontent.com/bcgov/agent-guardrails/main/scripts/git-setup.sh | bash
```

## What is not in this repo

- **Copilot instructions** — [bcgov/copilot-instructions](https://github.com/bcgov/copilot-instructions)
- **Personal instructions or bundling** — maintain in your own dotfiles

## Relationship to the AI stack

```
copilot-instructions  →  shared work standards (text, ≤4k)
agent-guardrails      →  enforcement (hooks, shell wrappers)  ← you are here
dotfiles (personal)   →  merge work+personal, symlink tools, optional guardrails wrapper
```

## Contributing

Submit PRs to improve shared guardrails. Test locally with `./setup.sh` before opening a PR.

## Attribution

Shell safety patterns from [bcgov/copilot-instructions](https://github.com/bcgov/copilot-instructions) (guardrails split). Git setup patterns from [GitButler](https://blog.gitbutler.com/how-git-core-devs-configure-git).
