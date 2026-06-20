#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)

# Detect if running via curl | bash (no local setup assets available)
if [[ ! -f "$SCRIPT_DIR/scripts/git-safety.sh" ]]; then
  echo "Installer running in standalone/curl mode. Fetching setup assets..."
  TEMP_SETUP_DIR=$(mktemp -d)

  curl -fsSL "https://github.com/bcgov/agent-guardrails/archive/refs/heads/main.tar.gz" \
    | tar -xz -C "$TEMP_SETUP_DIR" --strip-components=1

  SCRIPT_DIR="$TEMP_SETUP_DIR"
  trap 'rm -rf "$TEMP_SETUP_DIR"' EXIT
fi

HOOKS_DIR="$HOME/.githooks"
BIN_DIR="$HOME/.local/bin"

_real_git() {
  local git_bin=""
  while IFS= read -r dir; do
    [[ "$dir" == "$BIN_DIR" ]] && continue
    if [[ -x "$dir/git" ]]; then
      git_bin="$dir/git"
      break
    fi
  done < <(printf '%s\n' "$PATH" | tr ':' '\n')

  if [[ -z "${git_bin:-}" ]]; then
    echo "ERROR: Real git binary not found in PATH." >&2
    exit 127
  fi

  "$git_bin" "$@"
}

install_gitleaks() {
  mkdir -p "$BIN_DIR"

  local os arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "ERROR: Unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  case "$os" in
    linux|darwin) ;;
    *) echo "ERROR: Unsupported OS: $os" >&2; exit 1 ;;
  esac

  set +e +o pipefail
  local json_data
  json_data=$(curl -fsSL --connect-timeout 5 "https://api.github.com/repos/gitleaks/gitleaks/releases/latest" 2>/dev/null)
  local curl_status=$?
  set -e -o pipefail

  local latest_url=""
  if [[ $curl_status -eq 0 ]] && [[ -n "$json_data" ]]; then
    latest_url=$(echo "$json_data" \
      | grep -Eo '"browser_download_url"\s*:\s*"[^"]+"' \
      | cut -d '"' -f 4 \
      | grep "gitleaks_.*_${os}_${arch}\.tar\.gz" \
      | head -n 1 || true)
  fi

  if [[ -n "${latest_url:-}" ]]; then
    echo "Downloading and installing latest gitleaks to $BIN_DIR..."
    set +e
    curl -fsSL --connect-timeout 10 "$latest_url" | tar -xz -C "$BIN_DIR" gitleaks 2>/dev/null
    local download_status=$?
    set -e
    if [[ $download_status -ne 0 ]]; then
      echo "WARNING: Failed to download or extract gitleaks. Skipping." >&2
    fi
  elif command -v gitleaks >/dev/null 2>&1; then
    echo "WARNING: Offline or unable to connect to api.github.com. Keeping existing gitleaks installation." >&2
  else
    echo "WARNING: Offline or unable to connect to api.github.com. Skipping gitleaks installation." >&2
  fi

  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "NOTE: Ensure $BIN_DIR is on your PATH to use gitleaks." >&2
  fi
}

install_hooks() {
  mkdir -p "$HOOKS_DIR"

  if [[ ! -f "$SCRIPT_DIR/scripts/hooks/pre-commit" ]]; then
    echo "ERROR: Hook file not found: $SCRIPT_DIR/scripts/hooks/pre-commit" >&2
    exit 1
  fi

  if [[ ! -f "$SCRIPT_DIR/scripts/hooks/pre-push" ]]; then
    echo "ERROR: Hook file not found: $SCRIPT_DIR/scripts/hooks/pre-push" >&2
    exit 1
  fi

  local timestamp
  timestamp=$(date +%s)

  if [[ -f "$HOOKS_DIR/pre-commit" ]]; then
    mv "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit.bak.$timestamp"
    echo "NOTE: Existing pre-commit hook backed up to $HOOKS_DIR/pre-commit.bak.$timestamp" >&2
  fi

  if [[ -f "$HOOKS_DIR/pre-push" ]]; then
    mv "$HOOKS_DIR/pre-push" "$HOOKS_DIR/pre-push.bak.$timestamp"
    echo "NOTE: Existing pre-push hook backed up to $HOOKS_DIR/pre-push.bak.$timestamp" >&2
  fi

  cp "$SCRIPT_DIR/scripts/hooks/pre-commit" "$HOOKS_DIR/pre-commit"
  cp "$SCRIPT_DIR/scripts/hooks/pre-push" "$HOOKS_DIR/pre-push"
  chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push"

  local current_hooks_path
  current_hooks_path=$(_real_git config --global --get core.hooksPath 2>/dev/null || true)

  if [[ -n "${current_hooks_path:-}" ]] && [[ "$current_hooks_path" != "$HOOKS_DIR" ]]; then
    echo "WARNING: Your global git core.hooksPath is currently set to: $current_hooks_path" >&2
    echo "This script will change it to: $HOOKS_DIR" >&2
    read -r -p "Do you want to proceed? [y/N]: " answer
    if [[ "${answer:-n}" != "y" ]] && [[ "${answer:-n}" != "Y" ]]; then
      echo "Skipped updating global core.hooksPath. Hooks were copied to $HOOKS_DIR." >&2
      return 0
    fi
  fi

  _real_git config --global core.hooksPath "$HOOKS_DIR"
}

cleanup_old_bashrc_safety() {
  local bashrc="$HOME/.bashrc"
  [[ -f "$bashrc" ]] || return 0

  echo "Cleaning up old safety wrapper definitions from ~/.bashrc..."

  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()

for pat in [
    r"# >>> bcgov/agent-guardrails >>>.*?# <<< bcgov/agent-guardrails <<<\n*",
    r"# >>> bcgov/copilot-instructions safety block >>>.*?# <<< bcgov/copilot-instructions safety block <<<\n*",
    r"# >>> dotfiles guardrails >>>.*?# <<< dotfiles guardrails <<<\n*",
    r"# Git Safety.*?\nexport -f git\n*",
    r"# GitHub CLI Safety.*?\nexport -f gh\n*",
    r"# AI POLICY \(bcgov/copilot-instructions\).*?\nexport -f (gh|npx)\n*",
]:
    content = re.sub(pat, "", content, flags=re.DOTALL)

content = re.sub(r"\n{3,}", "\n\n", content)
with open(path, "w") as f:
    f.write(content)
' "$bashrc"
  else
    echo "WARNING: python3 is not available. Skipping deep regex cleanup of old safety blocks." >&2
  fi
}

install_safety_functions() {
  local bashrc="$HOME/.bashrc"
  local git_safety="$SCRIPT_DIR/scripts/git-safety.sh"
  local timestamp
  timestamp=$(date +%s)

  if [[ ! -f "$git_safety" ]]; then
    echo "ERROR: Could not find safety source script at $git_safety" >&2
    return 1
  fi

  if [[ -f "$bashrc" ]]; then
    cp "$bashrc" "$bashrc.bak.$timestamp"
    echo "NOTE: Created backup of ~/.bashrc at $bashrc.bak.$timestamp" >&2
  fi

  cleanup_old_bashrc_safety

  mkdir -p "$HOOKS_DIR"
  cp "$git_safety" "$HOOKS_DIR/git-safety.sh"
  chmod +x "$HOOKS_DIR/git-safety.sh"
  echo "Copied safety script to $HOOKS_DIR/git-safety.sh"

  {
    echo ""
    echo "# >>> bcgov/agent-guardrails >>>"
    echo "if [ -f \"\$HOME/.githooks/git-safety.sh\" ]; then"
    echo "    . \"\$HOME/.githooks/git-safety.sh\""
    echo "    export BASH_ENV=\"\${BASH_ENV:-\$HOME/.githooks/git-safety.sh}\""
    echo "fi"
    echo "# <<< bcgov/agent-guardrails <<<"
  } >> "$bashrc"

  echo "Added safety function loader to ~/.bashrc"
}

install_gitleaks
install_hooks
cleanup_old_bashrc_safety

echo "Cleaning up any stale wrappers in $BIN_DIR..."
for cmd in git gh npm npx kubectl oc; do
  wrapper="$BIN_DIR/$cmd"
  if [[ -f "$wrapper" ]] \
    && head -n 5 "$wrapper" | grep -q '^#!/bin/bash' \
    && grep -qE 'bcgov/(copilot-instructions|agent-guardrails)' "$wrapper" \
    && grep -q 'safety wrapper' "$wrapper"; then
    echo "Removing wrapper script: $wrapper"
    rm -f "$wrapper"
  fi
done

if ! install_safety_functions; then
  echo "ERROR: Failed to install safety functions." >&2
  exit 1
fi

echo ""
echo "✅ Guardrails setup complete!"
echo "Git hooks:        Secrets blocked (Gitleaks) + main/master push blocked"
echo "Safety functions: Installed to ~/.bashrc (git, gh, npm, npx)"
echo "                  Clean, non-exported shell functions (no export -f)"
echo "Git config:       All git config commands blocked (use 'command git config' to bypass)"
echo ""
echo "Restart your terminal or run: source ~/.bashrc"

has_other_bash_env=false
if [[ -n "${BASH_ENV:-}" ]] && [[ "$BASH_ENV" != "$HOME/.githooks/git-safety.sh" ]]; then
  has_other_bash_env=true
fi

if [[ -f "$HOME/.bashrc" ]]; then
  if grep -v "git-safety.sh" "$HOME/.bashrc" | grep -q "export BASH_ENV="; then
    has_other_bash_env=true
  fi
fi

if [[ "$has_other_bash_env" == "true" ]]; then
  echo ""
  echo "######################################################################"
  echo "⚠️  CRITICAL WARNING: BASH_ENV IS ALREADY SET BY ANOTHER TOOL!"
  echo "   Current Environment Value: ${BASH_ENV:-(not set in current shell)}"
  echo ""
  echo "   Because BASH_ENV is already defined, the AI safety wrappers"
  echo "   will be BYPASSED in non-interactive sub-shells (like agent runners)."
  echo ""
  echo "   To enforce safety policies, you MUST manually edit your custom"
  echo "   BASH_ENV script to source our safety wrappers:"
  echo "   . \$HOME/.githooks/git-safety.sh"
  echo "######################################################################"
  echo ""
fi
