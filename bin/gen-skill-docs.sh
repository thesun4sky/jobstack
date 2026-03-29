#!/usr/bin/env bash
# gen-skill-docs.sh -- expand SKILL.md.tmpl → SKILL.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/templates"

# Read shared templates
PREAMBLE=$(cat "$TEMPLATE_DIR/preamble.md")
VOICE=$(cat "$TEMPLATE_DIR/voice.md")
ASK_USER=$(cat "$TEMPLATE_DIR/ask-user-question.md")
COMPLETION=$(cat "$TEMPLATE_DIR/completion-status.md")

count=0
for tmpl in "$ROOT_DIR"/*/SKILL.md.tmpl; do
  [ -f "$tmpl" ] || continue
  skill_dir=$(dirname "$tmpl")
  output="$skill_dir/SKILL.md"

  # Read template
  content=$(cat "$tmpl")

  # Replace placeholders
  content="${content//\{\{PREAMBLE\}\}/$PREAMBLE}"
  content="${content//\{\{VOICE\}\}/$VOICE}"
  content="${content//\{\{ASK_USER_QUESTION\}\}/$ASK_USER}"
  content="${content//\{\{COMPLETION_STATUS\}\}/$COMPLETION}"

  echo "$content" > "$output"
  count=$((count + 1))
  echo "  Generated: $(basename "$skill_dir")/SKILL.md"
done

echo "Done. $count skill(s) generated."
