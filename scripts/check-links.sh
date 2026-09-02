#!/usr/bin/env bash
# Verifies that every relative markdown link inside skills/ resolves, and that none point
# outside their own skill directory.
#
#   ./scripts/check-links.sh
#
# `validate-skills.sh` covers the frontmatter and naming rules from the Agent Skills spec but
# does not check links. That gap matters here: these skills lean on references/, and under
# progressive disclosure a dead link fails at the moment the agent reaches for the detail —
# long after anyone would notice reviewing the diff.
#
# A skill directory is the unit of distribution, so a link escaping it breaks as soon as the
# skill is installed on its own.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -d skills ]; then
  echo "No skills/ directory found." >&2
  exit 1
fi

checked=0
failed=0

while IFS= read -r md; do
  skill_name="$(printf '%s' "$md" | cut -d/ -f2)"
  skill_dir="skills/$skill_name"
  md_dir="$(dirname "$md")"
  abs_skill="$(cd "$skill_dir" && pwd)"

  # Pull `](target)` out of markdown links, then drop external links and bare anchors.
  links="$(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?:|mailto:|#)' || true)"

  while IFS= read -r link; do
    [ -z "$link" ] && continue

    target="${link%%#*}" # strip any #fragment
    [ -z "$target" ] && continue

    checked=$((checked + 1))
    resolved="$md_dir/$target"

    if [ ! -e "$resolved" ]; then
      echo "broken   $md -> $target"
      failed=$((failed + 1))
      continue
    fi

    abs_target="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
    case "$abs_target" in
      "$abs_skill"/*) ;;
      *)
        echo "escapes  $md -> $target (leaves $skill_dir)"
        failed=$((failed + 1))
        ;;
    esac
  done <<< "$links"
done < <(find skills -name '*.md' | sort)

echo
if [ "$failed" -gt 0 ]; then
  echo "FAIL  $checked relative links checked, $failed broken"
  exit 1
fi

echo "OK    $checked relative links checked"
