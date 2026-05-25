# Task Runner — Suggested Fixes

## Issue 1: Container exits before committing (work lost)

The container should commit a WIP auto-save on any exit, not just clean completion.
Add a trap in the container's entrypoint:

```bash
trap 'git add -A && git commit -m "WIP — auto-saved on interrupted run" 2>/dev/null || true' EXIT
```

This fires on crash, timeout, or SIGTERM. The final clean-commit message can overwrite it on success.

Alternatively, commit after each task is marked `[x]` rather than batching at the end — partial progress is always preserved that way.

---

## Issue 2: Fresh-start reset discards prior WIP commit

The runner resets to `main` at the start of each run, discarding any prior WIP commits on the branch.
It should check if the branch is already ahead of `main` and resume from there:

```bash
BRANCH="openspec/$CHANGE_NAME"
MAIN_HEAD=$(git rev-parse main)
BRANCH_HEAD=$(git rev-parse "$BRANCH" 2>/dev/null || echo "$MAIN_HEAD")

if [ "$BRANCH_HEAD" = "$MAIN_HEAD" ]; then
  git checkout -B "$BRANCH" "$MAIN_HEAD"   # fresh start
else
  git checkout "$BRANCH"                   # resume from prior WIP
fi
```

The reset should only happen with an explicit `--fresh` / `--restart` flag, not by default.
A prior WIP commit is almost always more useful than starting over.
