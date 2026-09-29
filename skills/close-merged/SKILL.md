---
name: close-merged
description: "Delete local branches that have been merged into master, and report PR number/state plus whether comments need addressing for the rest. Never deletes master."
allowed-tools:
  - "Bash"
---

Clean up local git branches that have already been merged into master, then report the status of every remaining branch: its PR number, PR state, and whether the PR has new comments that need to be addressed.

## Steps

1. **Fetch latest from origin** so merge status is accurate:
   ```
   git fetch origin --prune
   ```

2. **List branches** — both the merged candidates and the full local list (the full list drives the report):
   ```
   git branch --merged origin/master
   git branch
   ```
   Note any branch marked `+` — it is checked out in another worktree and cannot be checked out or deleted here.

3. **Filter protected branches** — never delete:
   - `master`

4. **Look up the PR for every local branch** — `gh pr list --head <branch> --state all --json number,title,state,mergedAt --limit 5` for every branch except `master`. A **merged** PR in this result is the **only** authoritative signal that a branch is safe to delete. Ambiki squash-merges PRs, so `git branch --merged` misses most real merges, AND it false-positives on empty placeholder branches whose tip commit is just an old master commit. Capture the PR number and state for every branch — the report needs them even when nothing is deleted.

5. **Delete branches — only when the PR is merged**:
   - **PR merged + git reports merged** → `git branch -d <branch>` (safe delete).
   - **PR merged + git does NOT report merged** (squash merge) → `git branch -D <branch>` (force delete).
   - **No merged PR** → **SKIP, even if `git branch --merged` flagged it.** This branch was never pushed/merged; the user may be using it as a placeholder for work-in-progress. Do not delete. Mention it in the report as "skipped — no merged PR (git flagged as merged, but likely a placeholder branch)".

6. **Check open PRs for comments needing attention** — one GraphQL query with an alias per PR (write it to `$CLAUDE_JOB_DIR/tmp/` or a temp file). For each open PR pull `reviewThreads(first: 100)` with `isResolved` and the last comment's `author.login`/`createdAt`, plus `comments(last: 15)` with author and date. Parse with `gh api graphql --jq` (this machine has no standalone `jq`; gh's built-in one works). Example fragment:
   ```
   fragment prFields on PullRequest {
     number
     reviewThreads(first: 100) { nodes { isResolved comments(last: 1) { nodes { author { login } createdAt } } } }
     comments(last: 15) { nodes { author { login } createdAt } }
   }
   ```
   A PR **needs attention (yes)** when either: an unresolved review thread's **last** comment is from someone other than the user (GitHub login `palamedes`), or the newest non-bot issue comment is from someone else and postdates the user's last comment. Unresolved threads where the user replied last are "awaiting reviewer", not "yes" — note them separately. Ignore `ambiki-bot`/`github-actions` comments.

7. **Report results** as a table plus notes:

   | Branch | PR | State | Comments to address |
   |---|---|---|---|
   | `je-fix/example` | #1234 | Open | Yes — 3 unresolved threads from reviewer |

   - State is Merged/Open/Closed; add "(checked out in another worktree)" where applicable.
   - Comments column: **Yes** (with a one-phrase why), **No**, or **No (awaiting reviewer — N open threads, you replied last)**.
   - List each branch that was deleted, and any skipped placeholder branches.

8. **Offer to bring still-open branches up to date with master** — after reporting, ask the user whether to merge `origin/master` into each still-open branch and push. Wait for their answer; do nothing automatically. Branches checked out in another worktree are always skipped (say so in the offer).
   - If they say yes, for each branch:
     1. **Guard the working tree**: if `git status --porcelain` (ignoring `__jellis_console.rb`) shows only a modified `Gemfile.lock`, discard it with `git checkout -- Gemfile.lock` — the running dev server regenerates the lock against whatever branch's Gemfile is checked out, and that drift blocks checkouts. Any **other** dirty file → stop and report; do not discard.
     2. `git checkout <branch>`
     3. `git merge --ff-only origin/<branch>` (ignore failure — local ahead is fine) so the merge lands on the remote tip.
     4. `git merge --no-edit origin/master` — on conflict, `git merge --abort`, note the branch, and continue with the next one; do not attempt to resolve.
     5. `git push` — only after a clean merge.
   - When finished, return to the branch the user started on and re-run the Gemfile.lock guard once more so the tree ends clean.
   - Report which branches were updated (with pushed ranges), which had conflicts, and which were skipped.
