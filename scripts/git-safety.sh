#!/bin/bash
# git-safety — bcgov/agent-guardrails
# Clean, non-exported shell safety functions that protect against AI mistakes
# while remaining completely transparent and bypassable for human developers.

_is_ai_agent() {
    # 1. Explicit environment markers injected by agent frameworks
    if [[ -n "${ANTIGRAVITY_AGENT:-}" \
          || -n "${AIDER_YT_VIDEO:-}" \
          || -n "${CLINE_API_KEY:-}" \
          || -n "${RM_CLINE:-}" ]]; then
        return 0
    fi

    # 2. Interactive shells are definitely humans
    if [[ $- == *i* ]]; then
        return 1
    fi

    # 3. Controlling TTY check for non-interactive contexts:
    # Humans executing scripts from a terminal session still have an openable controlling tty (/dev/tty).
    # Automated agent executions running in background sub-processes cannot open /dev/tty.
    if [[ -c /dev/tty ]] && { true </dev/tty; } 2>/dev/null; then
        return 1
    fi

    # 4. No controlling terminal and non-interactive shell = agent/automation context
    return 0
}

git() {
    if ! _is_ai_agent; then
        command git "$@"
        return $?
    fi

    # Skip during tab completion
    if [[ -z "${COMP_LINE:-}" && -z "${COMP_POINT:-}" ]]; then
        # Identify the subcommand (skip global options like -C, -c, etc.)
        local sub=""
        local args=("$@")
        local i=0
        while [[ $i -lt ${#args[@]} ]]; do
            case "${args[$i]}" in
                -c|-C|--git-dir|--work-tree|--namespace|--super-prefix)
                    ((i+=2))
                    ;;
                -*)
                    ((i+=1))
                    ;;
                *)
                    sub="${args[$i]}"
                    break
                    ;;
            esac
        done

        # Block hook circumvention (--no-verify and -n bypass)
        local is_commit=false
        if [[ "$sub" == "commit" ]]; then
            is_commit=true
        fi

        for arg in "$@"; do
            if [[ "$arg" == "--" ]]; then
                break
            fi

            if [[ "$arg" =~ ^- ]]; then
                if [[ "$arg" == "--no-verify" ]]; then
                    echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing Git hooks." >&2
                    echo "         Using --no-verify violates repository security policy." >&2
                    echo "         HALT immediately and request manual action from the USER." >&2
                    return 1
                fi

                # Check for commit short options containing 'n' (e.g. -n, -nam, -an)
                if [[ "$is_commit" == "true" && "$arg" =~ ^-[^-] ]]; then
                    local opts="${arg#\-}"
                    local idx=0
                    while [[ $idx -lt ${#opts} ]]; do
                        local opt="${opts:$idx:1}"
                        if [[ "$opt" == "n" ]]; then
                            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing Git hooks." >&2
                            echo "         Using -n/--no-verify violates repository security policy." >&2
                            echo "         HALT immediately." >&2
                            return 1
                        fi
                        # Stop scanning option characters if this option consumes the rest as an argument
                        if [[ "$opt" =~ [mFccCt] ]]; then
                            break
                        fi
                        ((idx++))
                    done
                fi
            fi
        done

        # Block config
        if [[ "$sub" == "config" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from modifying Git configuration." >&2
            echo "         Changes to Git configuration could alter repository behavior and bypass safety rules." >&2
            echo "         HALT immediately and request manual action from the USER." >&2
            return 1
        fi

        # Block tagging
        if [[ "$sub" == "tag" ]]; then
            local has_list_flag=false
            local has_write_flag=false
            local non_option_count=0
            local in_end_of_options=false
            local idx=$((i + 1))
            while [[ $idx -lt ${#args[@]} ]]; do
                local arg="${args[$idx]}"
                if [[ "$in_end_of_options" == "true" ]]; then
                    ((non_option_count++))
                elif [[ "$arg" == "--" ]]; then
                    in_end_of_options=true
                else
                    case "$arg" in
                        -d|--delete|-a|--annotate|-s|--sign|-u*|--local-user*|-f|--force|-m*|--message*|-F*|--file*)
                            has_write_flag=true
                            ;;
                        -v|--verify|-l|--list|-n*|--contains*|--no-contains*|--points-at*|--merged*|--no-merged*|--sort*|--format*|--color*|--column*)
                            has_list_flag=true
                            ;;
                        -*)
                            # Other options
                            ;;
                        *)
                            ((non_option_count++))
                            ;;
                    esac
                fi
                ((idx++))
            done

            local is_write=false
            if [[ $non_option_count -gt 0 && "$has_list_flag" != "true" ]]; then
                is_write=true
            fi
            if [[ "$has_write_flag" == "true" ]]; then
                is_write=true
            fi

            if [[ "$is_write" == "true" ]]; then
                echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from tagging commits." >&2
                echo "         AI is not allowed to manage git tags or cut releases." >&2
                echo "         HALT immediately and request manual action from the USER." >&2
                return 1
            fi
        fi

        # Block destructive squashing / interactive rebase / amending
        local is_destructive=false
        if [[ "$sub" == "rebase" ]]; then
            for arg in "$@"; do
                if [[ "$arg" == "-i" || "$arg" == "--interactive" || "$arg" == "squash" || "$arg" == "fixup" || "$arg" == "--autosquash" ]]; then
                    is_destructive=true
                    break
                fi
            done
        elif [[ "$sub" == "merge" ]]; then
            for arg in "$@"; do
                if [[ "$arg" == "--squash" || "$arg" == "squash" ]]; then
                    is_destructive=true
                    break
                fi
            done
        elif [[ "$sub" == "commit" ]]; then
            for arg in "$@"; do
                if [[ "$arg" == "--" ]]; then
                    break
                fi
                if [[ "$arg" == "--amend" ]]; then
                    echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from amending commits." >&2
                    echo "         Amending commits rewrites git history and violates repository rules." >&2
                    echo "         HALT immediately and request manual action from the USER." >&2
                    return 1
                fi
            done
        fi

        if [[ "$is_destructive" == "true" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from squashing commits or interactive rebasing." >&2
            echo "         Squashing destroys git history and makes change review difficult." >&2
            echo "         HALT immediately and request manual action from the USER." >&2
            return 1
        fi

        # Block tag pushes and force pushes in all forms
        if [[ "$sub" == "push" ]]; then
            for arg in "$@"; do
                if [[ "$arg" == "--" ]]; then
                    break
                fi
                if echo "$arg" | grep -qE "^(--tags|--follow-tags|refs/tags/|.*:refs/tags/)"; then
                    echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from pushing tags." >&2
                    echo "         AI is not allowed to manage git tags or cut releases." >&2
                    echo "         HALT immediately and request manual action from the USER." >&2
                    return 1
                fi
                if [[ "$arg" == "--force" || "$arg" == "-f" || "$arg" == "--force-with-lease" || "$arg" =~ ^--force-with-lease= ]]; then
                    echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from force-pushing." >&2
                    echo "         Force-pushing rewrites history on remote branches." >&2
                    echo "         HALT immediately." >&2
                    return 1
                fi
            done
        fi
    fi

    command git "$@"
}

gh() {
    if ! _is_ai_agent; then
        command gh "$@"
        return $?
    fi

    # Skip during tab completion
    if [[ -z "${COMP_LINE:-}" && -z "${COMP_POINT:-}" ]]; then
        # Identify command and subcommand (skip global options like -R, --repo, etc.)
        local cmd=""
        local sub=""
        local args=("$@")
        local i=0
        while [[ $i -lt ${#args[@]} ]]; do
            case "${args[$i]}" in
                -R|--repo|--app|--host)
                    ((i+=2))
                    ;;
                -*)
                    ((i+=1))
                    ;;
                *)
                    if [[ -z "$cmd" ]]; then
                        cmd="${args[$i]}"
                    elif [[ -z "$sub" ]]; then
                        sub="${args[$i]}"
                        break
                    fi
                    ((i+=1))
                    ;;
            esac
        done

        if [[ "$cmd" == "release" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from managing GitHub Releases." >&2
            echo "         AI is not allowed to cut releases or manage git tags." >&2
            echo "         HALT immediately and request manual action from the USER." >&2
            return 1
        elif [[ "$cmd" == "repo" && "$sub" == "delete" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from deleting repositories." >&2
            echo "         Repository deletion is highly destructive and irreversible." >&2
            echo "         HALT immediately and request manual action from the USER." >&2
            return 1
        elif [[ "$cmd" == "secret" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from managing repository secrets." >&2
            echo "         Secret management must be handled directly by the USER." >&2
            echo "         HALT immediately." >&2
            return 1
        elif [[ "$cmd" == "issue" || "$cmd" == "pr" ]]; then
            if [[ "$sub" == "comment" || "$sub" == "review" ]]; then
                echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from commenting on or reviewing Issues or Pull Requests." >&2
                echo "         Posting comments or reviews simulates human discussion/review and violates impersonation policies." >&2
                echo "         HALT immediately. Output the details to the chat for the USER to post manually." >&2
                return 1
            elif [[ "$cmd" == "pr" && ( "$sub" == "merge" || "$sub" == "close" ) ]]; then
                echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from merging or closing Pull Requests." >&2
                echo "         Under shared agent-instructions policy, merge/close must be executed manually by the USER." >&2
                echo "         Do NOT attempt to bypass this block using absolute paths, alternate flags, or command overrides." >&2
                echo "         HALT immediately and report to the user." >&2
                return 1
            fi

            for arg in "$@"; do
                if [[ "$arg" == "-c" || "$arg" == "--comment" ]]; then
                    echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from posting PR/Issue comments." >&2
                    echo "         Using -c/--comment on gh $cmd $sub posts comments under human credentials." >&2
                    echo "         HALT immediately. Output the comment content to chat for the USER to post manually." >&2
                    return 1
                fi
            done
        elif [[ "$cmd" == "api" ]]; then
            local method="GET"
            local has_data=false
            local idx=0
            local raw_args=("$@")
            while [[ $idx -lt ${#raw_args[@]} ]]; do
                case "${raw_args[$idx]}" in
                    -X|--method)
                        method="$(echo "${raw_args[$((idx+1))]}" | tr '[:lower:]' '[:upper:]')"
                        ((idx+=2))
                        ;;
                    -f|-F|--field|--raw-field|--input)
                        has_data=true
                        ((idx+=2))
                        ;;
                    *)
                        ((idx+=1))
                        ;;
                esac
            done

            if [[ "$has_data" == "true" && "$method" == "GET" ]]; then
                method="POST"
            fi

            if [[ "$method" != "GET" ]]; then
                for arg in "$@"; do
                    if [[ "$arg" =~ /comments(/|$) || "$arg" =~ /reviews(/|$) ]]; then
                        echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from creating or updating comments/reviews via GitHub API." >&2
                        echo "         HALT immediately. Output the message to chat for the USER to post manually." >&2
                        return 1
                    fi
                done
            fi
        fi
    fi

    command gh "$@"
}

npm() {
    if ! _is_ai_agent; then
        command npm "$@"
        return $?
    fi

    # Skip during tab completion
    if [[ -z "${COMP_LINE:-}" && -z "${COMP_POINT:-}" ]]; then
        # Block environment-based bypass vector
        if [[ -n "${NPM_CONFIG_LEGACY_PEER_DEPS:-}" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing peer dependencies." >&2
            echo "         NPM_CONFIG_LEGACY_PEER_DEPS environment variable must not be set." >&2
            echo "         HALT immediately and resolve peer dependency conflicts cleanly." >&2
            return 1
        fi

        # Block flag-based bypass
        for arg in "$@"; do
            if [[ "$arg" == "--legacy-peer-deps" || "$arg" =~ ^--legacy-peer-deps= ]]; then
                echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing peer dependencies." >&2
                echo "         npm with --legacy-peer-deps is strictly forbidden." >&2
                echo "         HALT immediately and resolve peer dependency conflicts cleanly." >&2
                return 1
            fi
        done
    fi

    command npm "$@"
}

npx() {
    if ! _is_ai_agent; then
        command npx "$@"
        return $?
    fi

    # Skip during tab completion
    if [[ -z "${COMP_LINE:-}" && -z "${COMP_POINT:-}" ]]; then
        # Block environment-based bypass vector
        if [[ -n "${NPM_CONFIG_LEGACY_PEER_DEPS:-}" ]]; then
            echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing peer dependencies." >&2
            echo "         NPM_CONFIG_LEGACY_PEER_DEPS environment variable must not be set." >&2
            echo "         HALT immediately and resolve peer dependency conflicts cleanly." >&2
            return 1
        fi

        # Block flag-based bypass
        for arg in "$@"; do
            if [[ "$arg" == "--legacy-peer-deps" || "$arg" =~ ^--legacy-peer-deps= ]]; then
                echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from bypassing peer dependencies." >&2
                echo "         npx with --legacy-peer-deps is strictly forbidden." >&2
                echo "         HALT immediately and resolve peer dependency conflicts cleanly." >&2
                return 1
            fi
        done
    fi

    command npx "$@"
}

kubectl() {
    if _is_ai_agent; then
        echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from running Kubernetes (kubectl) commands." >&2
        echo "         Access to Kubernetes clusters is restricted." >&2
        echo "         HALT immediately and request manual action from the USER." >&2
        return 1
    fi

    command kubectl "$@"
}

oc() {
    if _is_ai_agent; then
        echo "BLOCKED: AI Agents are STRICTLY FORBIDDEN from running OpenShift (oc) commands." >&2
        echo "         Access to OpenShift is restricted." >&2
        echo "         HALT immediately and request manual action from the USER." >&2
        return 1
    fi

    command oc "$@"
}

