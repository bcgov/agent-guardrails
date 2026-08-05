#!/usr/bin/env bash
# ponytail: tiny deny/allow smoke check — fails if policy logic regresses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/scripts/agent-hook-validator.py"

assert_deny() {
  local cmd="$1"
  if printf '%s' "{\"command\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")}" \
    | python3 "$V" >/dev/null 2>&1; then
    echo "FAIL: expected deny: $cmd" >&2
    exit 1
  fi
}

assert_allow() {
  local cmd="$1"
  if ! printf '%s' "{\"command\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")}" \
    | python3 "$V" >/dev/null 2>&1; then
    echo "FAIL: expected allow: $cmd" >&2
    exit 1
  fi
}

assert_deny 'gh pr close 15'
assert_deny 'gh issue close 1'
assert_deny 'gh pr close 15 --comment x'
assert_deny 'gh pr comment 15 --body x'
assert_deny 'gh pr review 15 --approve'
assert_deny 'gh pr merge 15'
assert_deny 'gh release create v1.0.0'
assert_deny 'gh repo delete owner/repo'
assert_deny 'gh api -X PATCH repos/o/r/pulls/1 -f state=closed'
assert_deny 'git tag v1.0.0'
assert_deny 'git push --force'
assert_allow 'gh pr create --fill'
assert_allow 'gh pr edit 15 --title x'
assert_allow 'gh pr view 15'
assert_allow 'git commit -m msg'
assert_allow 'git push -u origin HEAD'

echo "self-check OK"
