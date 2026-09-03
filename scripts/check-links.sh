#!/usr/bin/env bash
# Verifies that every relative link inside skills/ resolves, that none point outside their own
# skill directory, and that every #fragment names a heading that exists.
#
#   ./scripts/check-links.sh
#
# `validate-skills.sh` covers the frontmatter and naming rules from the Agent Skills spec but
# does not check links. That gap matters here: these skills lean on references/, and under
# progressive disclosure a dead link fails at the moment the agent reaches for the detail —
# long after anyone would notice reviewing the diff.
#
# A skill directory is the unit of distribution, so a link escaping it breaks as soon as the
# skill is installed on its own. Paths are resolved to their physical location before that
# comparison, because a symlink out of the directory escapes it just as surely as `../`.
#
# Inline links, reference definitions and HTML href/src attributes are all checked, because a
# dead link is dead in whichever form it was written. Fenced code blocks are skipped: an `href`
# or a `# comment` inside a sample is sample text, not a link or a heading.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -d skills ]; then
  echo "No skills/ directory found." >&2
  exit 1
fi

# Prints the lines of $1 that sit outside fenced code blocks. A fence closes only on a run of
# the same character, at least as long as the run that opened it, with nothing but space after
# it. That is the CommonMark rule, and it is what stops a ```-fence shown inside a longer fence
# from closing it early and spilling sample code into the prose. Indentation is ignored rather
# than capped at CommonMark's three spaces, because the cap is relative to the containing block:
# measured from column 0 it would stop seeing fences nested in list items, and reading sample
# code as prose invents failures, where the reverse only misses links.
prose_lines() {
  local line trimmed run rest fence_char='' fence_len=0
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    run=''
    case "$trimmed" in
      '```'*) run="${trimmed%%[!\`]*}" ;;
      '~~~'*) run="${trimmed%%[!~]*}" ;;
    esac
    if [ -n "$run" ]; then
      rest="${trimmed#"$run"}"
      if [ -z "$fence_char" ]; then
        fence_char="${run:0:1}"
        fence_len="${#run}"
        continue
      fi
      if [ "${run:0:1}" = "$fence_char" ] && [ "${#run}" -ge "$fence_len" ] && [ -z "${rest//[[:space:]]/}" ]; then
        fence_char=''
        fence_len=0
        continue
      fi
    fi
    if [ -n "$fence_char" ]; then
      continue
    fi
    printf '%s\n' "$line"
  done < "$1"
}

# Prints every link target in $1 that points somewhere local — schemes and `//host/path` are
# somebody else's problem — from inline `](target)` links, reference definitions `[label]:
# target`, and HTML `href="..."` / `src="..."` attributes.
link_targets() {
  local prose
  prose="$(prose_lines "$1")"
  {
    printf '%s\n' "$prose" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//' || true
    printf '%s\n' "$prose" | grep -oE '^ {0,3}\[[^]^][^]]*\]:[[:space:]]*[^[:space:]]+' | sed -E 's/^.*\]:[[:space:]]*//' || true
    printf '%s\n' "$prose" | grep -oiE '(href|src)[[:space:]]*=[[:space:]]*("[^"]*"|'\''[^'\'']*'\''|[^[:space:]">'\'']+)' | sed -E 's/^[^=]*=[[:space:]]*//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' || true
  } | grep -viE '^(https?:|mailto:|//)' || true
}

# Prints the physical path of the existing file or directory $1. Symlinks are resolved, both in
# the parent directories and in the final component itself.
real_path() {
  local path="$1" dir base link hops=0
  while :; do
    dir="$(dirname -- "$path")"
    base="$(basename -- "$path")"
    dir="$(cd -- "$dir" && pwd -P)" || return 1
    path="$dir/$base"
    if [ ! -L "$path" ]; then
      break
    fi
    hops=$((hops + 1))
    if [ "$hops" -gt 40 ]; then
      return 1
    fi
    link="$(readlink -- "$path")"
    case "$link" in
      /*) path="$link" ;;
      *) path="$dir/$link" ;;
    esac
  done
  if [ -d "$path" ]; then
    path="$(cd -- "$path" && pwd -P)" || return 1
  fi
  printf '%s\n' "$path"
}

# Returns 0 when the newline-delimited list $1 contains $2 as a whole line.
list_has() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# Prints the anchor of every ATX heading in $1, one per line, in document order.
heading_slugs() {
  local text base slug n emitted=''
  while IFS= read -r text; do
    # GitHub slugs the heading as rendered: link syntax collapses to its text, punctuation is
    # dropped, and what is left is lowercased with spaces as hyphens. `tr` cannot classify
    # Unicode, so the punctuation this repo's prose uses is named outright and other non-ASCII
    # characters are kept, which is what GitHub does with letters. Case folding is ASCII-only.
    base="$(printf '%s' "$text" |
      sed -E 's/!?\[([^]]*)\]\([^)]*\)/\1/g; s/—|–|―|‘|’|“|”|…//g' |
      tr '[:upper:]' '[:lower:]' |
      tr -d '\000-\037\041-\054\056\057\072-\100\133-\136\140\173-\177' |
      tr ' ' '-')"
    if [ -z "$base" ]; then
      continue
    fi
    # A taken slug takes the first free -1, -2, ... suffix. Skipping a suffix that is already
    # some other heading's anchor is what GitHub does, and it is why `A`, `A-1`, `A` ends in
    # `a`, `a-1`, `a-2` rather than handing out `a-1` twice.
    slug="$base"
    n=0
    while list_has "$emitted" "$slug"; do
      n=$((n + 1))
      slug="$base-$n"
    done
    emitted="$emitted$slug"$'\n'
    printf '%s\n' "$slug"
  # The closing `#`s of `## Setup ##` are delimiters, not text, so they go before slugging.
  done < <(prose_lines "$1" | sed -nE -e 's/[[:space:]]+#+[[:space:]]*$//' -e 's/^#{1,6}[[:space:]]+(.*[^[:space:]])[[:space:]]*$/\1/p')
}

# Returns 0 when $2 is the anchor of a heading in the markdown file $1.
has_anchor() {
  local slugs
  slugs="$(heading_slugs "$1")"
  list_has "$slugs" "$2"
}

checked=0
failed=0

while IFS= read -r -d '' md; do
  # Not `cut`: it works a line at a time, so a newline in a filename would split the path.
  skill_name="${md#skills/}"
  skill_name="${skill_name%%/*}"
  skill_dir="skills/$skill_name"
  md_dir="$(dirname "$md")"
  abs_skill="$(cd "$skill_dir" && pwd -P)"

  links="$(link_targets "$md")"

  while IFS= read -r link; do
    [ -z "$link" ] && continue

    # A path may be wrapped in <> or followed by a "title"; keep the path alone.
    case "$link" in
      '<'*) link="${link#<}"; link="${link%%>*}" ;;
      *) link="${link%%[[:space:]]*}" ;;
    esac
    [ -z "$link" ] && continue

    target="${link%%#*}"
    fragment=''
    case "$link" in
      *#*) fragment="${link#*#}" ;;
    esac

    checked=$((checked + 1))

    # A bare #fragment points at a heading in this same file.
    if [ -z "$target" ]; then
      if [ -n "$fragment" ] && ! has_anchor "$md" "$fragment"; then
        echo "anchor   $md -> $link (no heading in $md)"
        failed=$((failed + 1))
      fi
      continue
    fi

    resolved="$md_dir/$target"

    if [ ! -e "$resolved" ]; then
      echo "broken   $md -> $target"
      failed=$((failed + 1))
      continue
    fi

    abs_target="$(real_path "$resolved")"
    case "$abs_target" in
      "$abs_skill" | "$abs_skill"/*) ;;
      *)
        echo "escapes  $md -> $target (leaves $skill_dir)"
        failed=$((failed + 1))
        continue
        ;;
    esac

    # Anchors are only checkable in markdown, which is the only place they are used.
    if [ -n "$fragment" ] && [ -f "$resolved" ] && [ "${resolved##*.}" = "md" ]; then
      if ! has_anchor "$resolved" "$fragment"; then
        echo "anchor   $md -> $link (no heading in $target)"
        failed=$((failed + 1))
      fi
    fi
  done <<< "$links"
done < <(find skills -type f -name '*.md' -print0 | sort -z)

echo
if [ "$failed" -gt 0 ]; then
  echo "FAIL  $checked relative links checked, $failed broken"
  exit 1
fi

echo "OK    $checked relative links checked"
