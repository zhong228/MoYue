#!/bin/bash
# The fidelity loop's isolated working copies.
#
#   create   worktrees of Yuedu-reader and YueduCoreText on branch loop/fidelity,
#            and a workspace that builds the app against that package checkout
#   status   where they are, what they hold, how far they are from main
#   remove   remove both worktrees; refuses while either holds uncommitted work
#
# The loop edits only these copies. The main checkouts keep the oracle it is
# scored with (docs/browser-layout/fidelity-loop/LOOP.md).
#
# Environment:
#   YUEDU_PACKAGE_REPO    the YueduCoreText checkout (default: ../YueduCoreText beside this repo)
#   YUEDU_FIDELITY_LOOP   where the copies go (default: ../Yuedu-fidelity-loop beside this repo)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$(cd "$HERE/../.." && pwd)"
PACKAGE="${YUEDU_PACKAGE_REPO:-$(dirname "$READER")/YueduCoreText}"
LOOP="${YUEDU_FIDELITY_LOOP:-$(dirname "$READER")/Yuedu-fidelity-loop}"
BRANCH="loop/fidelity"

# Build inputs and agent instructions that git ignores, so a fresh worktree lacks them.
LOCAL_FILES=(GoogleService-Info.plist AGENTS.md .codex/config.toml .codex/agents/fidelity-verifier.toml)

add_worktree() {
  local repo="$1" target="$2"
  if [[ -e "$target" ]]; then
    echo "exists: $target"
    return
  fi
  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    echo "note: $repo has uncommitted changes; the worktree starts from its committed main, without them"
  fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$repo" worktree add "$target" "$BRANCH"
  else
    git -C "$repo" worktree add -b "$BRANCH" "$target" main
  fi
}

case "${1:-}" in
  create)
    [[ -d "$PACKAGE/.git" ]] || { echo "no YueduCoreText checkout at $PACKAGE" >&2; exit 1; }
    mkdir -p "$LOOP"
    add_worktree "$READER" "$LOOP/Yuedu-reader"
    add_worktree "$PACKAGE" "$LOOP/YueduCoreText"
    for name in "${LOCAL_FILES[@]}"; do
      if [[ -f "$READER/$name" && ! -e "$LOOP/Yuedu-reader/$name" ]]; then
        mkdir -p "$(dirname "$LOOP/Yuedu-reader/$name")"
        cp "$READER/$name" "$LOOP/Yuedu-reader/$name"
        echo "copied $name"
      fi
    done
    # A workspace that lists a package folder builds that folder in place of
    # the remote package the project names.
    mkdir -p "$LOOP/Loop.xcworkspace"
    cat > "$LOOP/Loop.xcworkspace/contents.xcworkspacedata" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0">
  <FileRef location="group:Yuedu-reader/Yuedu-Reader.xcodeproj"/>
  <FileRef location="group:YueduCoreText"/>
</Workspace>
XML
    if ! python3 "$HERE/fidelity.py" lock --check --tree "$LOOP/Yuedu-reader"; then
      echo "!! the loop worktree does not hold the oracle files this checkout is locked to." >&2
      echo "   Commit the loop scaffold on main first, then: git -C '$LOOP/Yuedu-reader' merge main" >&2
      exit 2
    fi
    # Without this the workspace is ignored and every build silently uses the
    # published package instead of the loop's engine checkout.
    if ! grep -q 'YUEDU_WORKSPACE' "$LOOP/Yuedu-reader/scripts/xctest.sh"; then
      echo "!! the loop worktree's scripts/xctest.sh does not build from a workspace (YUEDU_WORKSPACE)." >&2
      echo "   Commit that change on main first, then: git -C '$LOOP/Yuedu-reader' merge main" >&2
      exit 2
    fi
    echo
    echo "loop copies ready in $LOOP"
    echo "build and test there with: YUEDU_WORKSPACE=$LOOP/Loop.xcworkspace bash scripts/xctest.sh -- …"
    ;;
  status)
    for pair in "$READER:$LOOP/Yuedu-reader" "$PACKAGE:$LOOP/YueduCoreText"; do
      repo="${pair%%:*}"; tree="${pair#*:}"
      if [[ ! -d "$tree" ]]; then echo "missing: $tree"; continue; fi
      echo "== $tree"
      echo "   branch: $(git -C "$tree" branch --show-current)  head: $(git -C "$tree" log -1 --format='%h %s')"
      echo "   ahead of main: $(git -C "$repo" rev-list --count "main..$BRANCH")  behind main: $(git -C "$repo" rev-list --count "$BRANCH..main")"
      echo "   uncommitted files: $(git -C "$tree" status --porcelain | wc -l | tr -d ' ')"
    done
    ;;
  remove)
    # Both or neither: check every copy before removing any.
    # Ignored local copies do not count as work; anything tracked or untracked-unignored does.
    for tree in "$LOOP/Yuedu-reader" "$LOOP/YueduCoreText"; do
      if [[ -d "$tree" && -n "$(git -C "$tree" status --porcelain)" ]]; then
        echo "!! $tree holds uncommitted work; commit or discard it yourself first" >&2
        exit 1
      fi
    done
    for pair in "$READER:$LOOP/Yuedu-reader" "$PACKAGE:$LOOP/YueduCoreText"; do
      repo="${pair%%:*}"; tree="${pair#*:}"
      [[ -d "$tree" ]] || continue
      git -C "$repo" worktree remove "$tree"
      echo "removed $tree (branch $BRANCH kept)"
    done
    rm -rf "$LOOP/Loop.xcworkspace"
    rmdir "$LOOP" 2>/dev/null || true
    ;;
  *)
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
