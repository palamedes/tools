---
name: eod
description: "Generate End of Day teammate report listing today's GitHub PRs across all Ambiki org repos plus any free-form activities passed as arguments. Outputs ready-to-paste text — never asks questions."
argument-hint: "[comma-separated extras like 'meetings, pr reviews, met with kim']"
allowed-tools:
  - "Bash"
---

Generate the user's end-of-day report. **Do not ask any clarifying questions.** Make best-effort judgments and emit the formatted block ready to paste into Slack/Teams.

## Output Format

```
End of Day - <Mon DDth>:
<pr-url> ~ <short description>
<pr-url> ~ <short description>
<branch-name> ~ <short description>     # local branch with today's commits but no PR yet
synced branches                          # only if PRs were dropped as sync-only
<extra-activity>
<extra-activity>
```

No bullet markers, no preamble, no trailing commentary — just the block above.

## Steps

### 1. Compute today's date with ordinal suffix

Format: `Mon Dth` (e.g. `Apr 25th`, `May 1st`, `Jun 22nd`, `Jul 3rd`).

Ordinal rules:
- `11`, `12`, `13` → `th`
- ends in `1` → `st`
- ends in `2` → `nd`
- ends in `3` → `rd`
- everything else → `th`

```bash
DAY=$(date +%-d)
MON=$(date +%b)
case $DAY in
  11|12|13) SFX="th" ;;
  *1) SFX="st" ;;
  *2) SFX="nd" ;;
  *3) SFX="rd" ;;
  *) SFX="th" ;;
esac
HEADER="End of Day - ${MON} ${DAY}${SFX}:"
```

### 2. Pull today's PRs from GitHub

**Use the user's GitHub events stream as the source of truth** — not `gh search prs`. Search filters like `--involves` + `--updated` are far too broad: they include PRs you're just assigned to or mentioned in, plus any PR that *anyone* updated today. The events API only returns what *you* actually did.

The GitHub API returns UTC timestamps, but "today" means the **local** calendar day. Never string-match the local date against `created_at` — that silently drops evening work (8pm ET is already tomorrow in UTC) and wrongly includes yesterday evening's. Compute the local day's UTC epoch window once and reuse it everywhere (events filter, commits API, merged-PR commit filtering):

```bash
USER=$(gh api user --jq .login)
TODAY=$(date +%Y-%m-%d)

# Local midnight -> epoch; end bound via -v+1d so DST-transition days stay correct (BSD/macOS date).
DAY_START=$(date -j -f '%Y-%m-%d %H:%M:%S' "$TODAY 00:00:00" +%s)
DAY_END=$(date -j -v+1d -f '%Y-%m-%d %H:%M:%S' "$TODAY 00:00:00" +%s)
DAY_START_ISO=$(date -u -r "$DAY_START" +%FT%TZ)
DAY_END_ISO=$(date -u -r "$DAY_END" +%FT%TZ)

EVENTS=$(gh api "/users/$USER/events?per_page=100" --paginate --jq "
  [.[] | select((.created_at | fromdateiso8601) >= $DAY_START and (.created_at | fromdateiso8601) < $DAY_END) | select(.repo.name | startswith(\"Ambiki/\"))]
")
```

**Scope: every repo in the Ambiki org** (`Ambiki/ambiki`, `Ambiki/ambiki-gai`, docs, gh-ci, etc.), not just the main app — work regularly spans them. Personal repos (`palamedes/*`) stay out of the report; this is a work EOD. Track each event's `repo.name` alongside its PR number and use that repo in every downstream `gh` command — never hardcode `Ambiki/ambiki`.

From `$EVENTS`, collect PR numbers from each event type:

| Event type                       | How to extract PR number                                           |
|----------------------------------|--------------------------------------------------------------------|
| `PullRequestEvent`               | `.payload.pull_request.number`                                     |
| `PullRequestReviewEvent`         | `.payload.pull_request.number`                                     |
| `PullRequestReviewCommentEvent`  | `.payload.pull_request.number`                                     |
| `IssueCommentEvent`              | `.payload.issue.number` *only if* `.payload.issue.pull_request` exists |
| `PushEvent`                      | Branch is `.payload.ref` (strip `refs/heads/`); look up PR with `gh pr list --head <branch> --repo <event's repo.name> --state all --json number,title,url` |

Skip everything else (e.g. `CreateEvent` for branch creation, `DeleteEvent`, `WatchEvent`).

After collecting numbers, **de-dupe** and fetch each PR's title + creation date:

```bash
gh pr view <num> --repo <pr's repo> --json number,title,url,createdAt
```

For each PR, determine whether it was **opened today** or is an **older PR** the user touched today:

- **Opened today** → the events stream has a `PullRequestEvent` with `payload.action == "opened"` for this PR number from the user. Format with title only:
  ```
  <url> ~ <title>
  ```

- **Older PR (not opened today)** → append a short summary of *what the user did today* on that PR. Format:
  ```
  <url> ~ <title> ~ <today's work summary>
  ```

  Generating the "today's work summary":
  1. **If user pushed commits today** (PushEvent on this PR's branch): the events API does **not** return commit messages for private repos (the `payload.commits` is `null`). Use the commits API instead, scoped to the PR's branch, the user as author, and the local-day UTC window from step 2:
     ```bash
     gh api "/repos/<pr's repo>/commits?author=$USER&since=$DAY_START_ISO&until=$DAY_END_ISO&sha=<branch>" \
       --jq '.[] | {msg: (.commit.message | split("\n")[0]), parents: (.parents | length)}'
     ```
     - **If the branch no longer exists** (deleted after merge — the commits API 404s), fall back to the PR's own commit list, filtered to the same window:
       ```bash
       gh pr view <num> --repo <pr's repo> --json commits \
         --jq ".commits[] | select(.authoredDate >= \"$DAY_START_ISO\" and .authoredDate < \"$DAY_END_ISO\") | .messageHeadline"
       ```
     - Treat any commit with `parents >= 2` (or message starting with `Merge branch` / `Merge pull request`) as a **merge commit** — it's housekeeping, not work. A rebase (no merge commit, but commits whose authorship date is older than today rewritten onto today's tip) also counts as housekeeping with no real work.
     - Treat any commit whose subject ends with ` (#NNNN)` (a GitHub squash-merge artifact, e.g. `Add foo (#7547)`) as housekeeping too — those appear in feature branches' history right after a `master` sync because they were squashed onto master in a different PR. They are NOT this PR's work.
     - **Filter out merge commits and squash-merge artifacts**, then summarize the remaining commit subjects into **one terse phrase** (≤12 words). Don't list commits verbatim — write a single human summary like *"fixed layout spacing and added null-safe branch lookup"*.
     - **If after filtering only merge/rebase/sync activity remains** (i.e. the only thing the user did on this PR today was sync master or rebase), **do not list this PR** as its own line. Instead, set a flag so a single `synced branches` line is appended to the report (see step 4). If the user *also* reviewed or commented on the PR today, still drop the PR line — the sync rolls into `synced branches` and the review/comment activity is implicit.
  2. **Else if PR was merged into master today** (`PullRequestEvent` with `payload.action == "merged"` from this user, AND no real commits today on the branch): the summary is `merged`. **Drop these PR lines from the report entirely** — a PR whose only activity today is the merge has already shipped and adds noise to the EOD list. Do *not* roll them into `synced branches` (that line is reserved for sync-only branches that didn't ship).
     - If the PR was merged today AND had real commits today, keep the line and use the commits summary (the merge is implied by shipping).
  3. **Else if user only reviewed** (`PullRequestReviewEvent`): write `reviewed` (or `reviewed + commented` if both events present).
  4. **Else if user only commented** (`IssueCommentEvent` / `PullRequestReviewCommentEvent`): write `commented`.

  Keep the summary short and human — don't include commit SHAs, branch names, or PR numbers.

Title rules:
- Use the PR title as-is unless it's noisy.
- If excessively long (>120 chars), trim to the meaningful core.
- Sort by PR number ascending so the list reads chronologically.

### 2.5. Add local branches with today's work that have no PR

Some local branches may have commits authored today but no PR opened yet (in-progress work the user wants visible in EOD). For each such branch, emit a line `<branch-name> ~ <work summary>` (no URL — there is no PR).

```bash
USER_EMAIL=$(git config user.email)

# Skip this step if not in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit_step

# Branches share a single .git dir across worktrees, so for-each-ref sees them all.
git for-each-ref refs/heads/ --format='%(refname:short)' | while read branch; do
  # Today's commits on this branch authored by the user, excluding merges.
  # NOTE: git interprets --since in LOCAL time, so the plain local date is correct here —
  # do NOT convert this one to the UTC window used for the GitHub API calls.
  COMMITS=$(git log "$branch" --since="${TODAY}T00:00:00" --author="$USER_EMAIL" --no-merges --format='%s' 2>/dev/null)
  [ -z "$COMMITS" ] && continue

  # Drop squash-merge artifacts ("Some title (#7547)") — those came from master, not this branch.
  REAL=$(printf '%s\n' "$COMMITS" | grep -Ev ' \(#[0-9]+\)$' || true)
  [ -z "$REAL" ] && continue

  # Skip if this branch already has a PR (it's already covered in step 2's PR loop).
  # Derive the repo from the checkout itself (works from any Ambiki repo, e.g. ambiki-gai).
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
  HAS_PR=$(gh pr list --head "$branch" --repo "$REPO" --state all --json number --jq 'length' 2>/dev/null)
  [ "${HAS_PR:-0}" != "0" ] && continue

  # Emit: branch ~ summary  (the summarization happens in your model output, ≤12 words)
  printf '%s\t%s\n' "$branch" "$REAL"
done
```

For each emitted branch, summarize the commit subjects into one terse phrase (≤12 words), same rules as PR commit summaries. Format:

```
<branch-name> ~ <work summary>
```

Sort branch lines alphabetically. Place them in the report **after** the PR lines and **before** `synced branches` / extras (see step 4).

If a branch has *no* real commits today (only merges or squash-merge artifacts), do not emit a line for it — it's already accounted for by `synced branches` if relevant.

### 3. Process `$ARGUMENTS` for extra activities

If `$ARGUMENTS` is non-empty:
- Split on commas
- Trim whitespace from each piece
- Lowercase the first letter only if needed for consistency, otherwise leave as the user typed it
- Append each piece as its own plain line (no bullet marker, no URL prefix) AFTER the PR lines

### 4. Print the report

Order:
1. Header
2. PR lines (PRs from step 2 that survived the drop rules)
3. Local-branch lines (from step 2.5 — branches with today's commits but no PR)
4. `synced branches` — only if at least one PR was dropped as sync-only
5. Extras from `$ARGUMENTS`

Output exactly:
```
<HEADER>
<pr line 1>
<pr line 2>
...
<branch-without-pr line 1>
<branch-without-pr line 2>
...
synced branches        # only if at least one PR was sync-only
<extra 1>
<extra 2>
```

No commentary before or after. The user will copy/paste it directly.

## Edge cases

- **No PRs and no extras** → print `<HEADER>` followed by `(no GitHub activity today)`.
- **Only extras, no PRs** → print `<HEADER>` then the extras, no placeholder line.
- **Only PRs, no extras** → print `<HEADER>` then the PR lines.
- **`gh` auth/error** → print the error message and stop. Do not fabricate PRs.
- **Duplicates** (same PR returned twice) → de-dupe by PR number.

## Ground rules

1. **Never ask a question.** Always emit output.
2. **Never invent PR numbers or descriptions.** Only list PRs returned by `gh`.
3. **Stay terse.** Each line should be short and scannable.
4. **Plain output only.** No markdown headers, no code fences around the report itself, no "here's your report" preamble.
