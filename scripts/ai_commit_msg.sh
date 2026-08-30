#!/bin/sh
# Pre-fills the commit message from the staged diff, using the `claude` CLI and the
# style of the existing history. Meant to be called from a prepare-commit-msg hook.
# Set GEMBOY_AI_MSG=0 to skip it for one commit.

msg_file="$1"
source_type="${2:-}"

case "$source_type" in
  message | merge | squash | commit) exit 0 ;;
esac

[ "${GEMBOY_AI_MSG:-1}" = "0" ] && exit 0
command -v claude >/dev/null 2>&1 || exit 0

diff=$(git diff --cached --stat; git diff --cached -- ':(exclude)*.lock' ':(exclude)*.gem' | head -c 40000)
[ -z "$diff" ] && exit 0

history=$(git log --format='%s' -30)

runner=""
command -v timeout >/dev/null 2>&1 && runner="timeout 60"
command -v gtimeout >/dev/null 2>&1 && runner="gtimeout 60"

prompt="You write git commit subject lines.

Here are the last commit subjects of this repository, follow their tone, length and
capitalisation:
---
$history
---

Rules:
- output ONE line, nothing else: no body, no quotes, no code fences, no leading dash
- imperative mood, max 72 characters
- state what the change does, not the file names
- add a short parenthesis only when the impact is not obvious from the summary

Here is the staged diff:
---
$diff
---"

generated=$($runner claude -p "$prompt" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)
[ -z "$generated" ] && exit 0

generated=$(printf '%s' "$generated" | sed 's/^["'\''`]//; s/["'\''`]$//' | cut -c1-100)

printf '%s\n\n%s\n' "$generated" "$(cat "$msg_file")" > "$msg_file.ai" && mv "$msg_file.ai" "$msg_file"
exit 0
