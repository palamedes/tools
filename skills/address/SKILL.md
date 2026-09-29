---
name: address
description: "Work through code review feedback on a GitHub PR one comment at a time: research each ask, then fix it, push back, write a spec, or ask — one commit per comment, human-voice replies queued until the push is approved. Trigger on /address, 'address the review feedback', 'handle the PR comments'."
argument-hint: "[PR number or URL]"
---

Handle code review feedback on a pull request, one comment at a time. Never batch. Replies are QUEUED and only posted after the user approves the push at the end.

## Resolve the PR

- `/address 1234` → PR number 1234.
- A full PR URL → extract the number. If the URL's owner/repo doesn't match this repo's `origin`, stop and say so.
- No argument → find the PR for the current branch (`gh pr view --json number,url` resolves it). Exactly one open PR: use it. Zero or several: stop and ask which one.

## Setup (stop on any failure)

1. Verify `gh` is installed and authenticated (`gh auth status`). If not, stop with a clear message telling the user what to run.
2. Check the working tree is clean (`git status --porcelain`). Ignore `__jellis_console.rb` entirely — filter it out and never mention it. If anything else is dirty, stop and list exactly what's dirty. NEVER stash, discard, or commit the user's work to proceed.
3. Fetch PR state (`gh pr view <n> --json state,mergedAt,headRefName,author,url,title`). If the PR is closed or merged, say so and stop.
4. `gh pr checkout <n>` (handles forks correctly), then `git pull --ff-only`. If checkout fails because the branch is checked out in another worktree, stop and report which worktree — never force anything.
5. Record who I am: `gh api user --jq .login`. Feedback authored by this login is skipped everywhere below.

## Gather feedback

Feedback lives in three places; collect all three:

1. **Inline review comments** — use the GraphQL `reviewThreads` connection so resolution state comes along (get owner/repo from `gh repo view --json owner,name` first):

   ```
   gh api graphql -f query='query($owner:String!,$repo:String!,$number:Int!){
     repository(owner:$owner,name:$repo){ pullRequest(number:$number){
       reviewThreads(first:100){ nodes { isResolved isOutdated path line
         comments(first:50){ nodes { databaseId author{login} body url createdAt } } } } } } }' \
     -F owner=<owner> -F repo=<repo> -F number=<n>
   ```

2. **Review submission bodies** — `gh api repos/{owner}/{repo}/pulls/<n>/reviews`, keeping non-empty bodies.
3. **General conversation comments** — `gh api repos/{owner}/{repo}/issues/<n>/comments`.

**Skip** (this command must be safe to run twice):

- Resolved threads (`isResolved: true`).
- Anything authored by my own login.
- Threads whose most recent comment is mine — that means a previous run already replied.
- Review bodies / general comments that a later comment of mine already quotes or answers.
- Comments whose URL already appears in a commit message on this branch (`git log --grep`) — a previous run fixed it but may not have replied yet; note it in the summary instead of redoing it.

If nothing survives the filters, say the PR has no open feedback and stop.

**Present the list** before starting work: numbered, one line each — author, `file:line` (or "review body" / "PR comment"), and a one-line summary of the ask. Then start on item 1.

## Work through them, strictly one at a time

For each comment, in order:

### 1. Research first

Do not assume the reviewer is right. Read the code they're pointing at plus enough surrounding context to actually understand it. If they claim a bug, try to confirm it's real. If they cite a convention, grep the codebase to check whether it's actually followed. Search the web only for questions about an external library or standard that the repo can't answer. If the comment sits on a line that no longer exists because the code moved (thread is `isOutdated` or the anchor is gone), don't guess at what it referred to — the reply says so instead.

### 2. Decide: one of four outcomes

- **Fix it** — the ask is valid and small enough to just do.
- **Push back** — the ask is wrong, a misreading, or would make things worse. Draft a polite reply with the specific reason. Change no code. Pushing back is a legitimate outcome, not a failure.
- **Write a spec** — valid but too large for a drive-by fix, or it changes behavior in a way that needs a decision. Write a short markdown spec to `specs/` at the repo root: what was asked, why it's out of scope for this PR, what the change would involve, open questions. One page max. Commit it, and the queued reply points at it.
- **Ask the user** — ambiguous, or depends on product intent they haven't stated. Stop and ask (AskUserQuestion). Don't guess.

### 3. If fixing: minimal diff

Change only what that comment is about. No drive-by refactors, no reformatting untouched lines, no fixing unrelated things noticed along the way — note those for the final summary instead.

### 4. Verify (targeted, not the full suite)

Detect the project's tooling — check the repo's CLAUDE.md for stated commands first, then infer: Gemfile → `bundle exec rspec <spec files for the changed files>` and `bundle exec rubocop <changed files>`; package.json → its test script scoped to the change, plus its linter (in Ambiki, JS changes get `yarn run eslint <file>`). Run the spec files corresponding to what changed, plus any spec the comment itself touches, and lint the changed files. If a fix breaks something, fix that too or back the change out — never leave the branch broken. The full suite is not run per fix; that stays the user's call before merge.

### 5. Commit — one commit per comment

Each commit is reviewable and revertable on its own. The body references the comment by its URL (this is also the re-run idempotency marker). Follow the user's commit rules: short subject, blank line, body paragraphs as single unbroken lines (no hard wrap at 72), no Co-Authored-By or any AI attribution trailer, and pass the message with `-F <file>` — never `-m` with backticks.

### 6. Draft the reply — queue it, don't post it

Write the reply now, while context is fresh, but do NOT post it yet. Keep it with the item. For inline comments it will go to that thread via `POST repos/{owner}/{repo}/pulls/<n>/comments/<comment_id>/replies`; for a review body or general comment it will be a top-level `gh pr comment` that quotes (`> …`) the relevant line so it's clear what's being answered. Always pass bodies with `--body-file` / `-F body=@<file>` from the scratchpad.

## Reply voice (important)

Replies must read like the user typed them on their phone, not like a bot:

- Short. One to three sentences, usually one.
- Plain language: "fixed the null check", not "implemented defensive nil handling in the accessor path".
- First person, casual, contractions fine.
- No "Great catch!" / "Thanks for the thorough review!" preamble on every one — occasionally, when actually warranted, is fine.
- No bullet lists unless there are genuinely several separate things. No emoji unless the reviewer used them first.
- Never mention AI. No generated-with footers on commits or comments.

Good:

> Good catch, fixed.

> Changed it to use the existing helper instead.

> I think this one's already handled ... the caller checks for that a few lines up. Let me know if I'm reading it wrong.

> Fair point but I'd rather not do this here, it'd mean touching the auth flow and I want that in its own PR. Wrote it up as a spec, see specs/.

Bad (never this):

> Thank you for this excellent observation! I have refactored the method to leverage the existing utility function, thereby improving maintainability and reducing code duplication across the module.

## Re-review before pushing

After every comment is handled, make sure the next review round won't find something new, as best you can. If a review skill is available in this session (e.g. `/code-review`, `/review-pr` — don't assume a specific one exists), run it against the branch; otherwise review `git diff <merge-base>..HEAD` yourself with fresh eyes, paying closest attention to the code this run changed. Then:

- A finding in code this run touched: fix it (its own commit, noted in the summary).
- A finding elsewhere in the PR: don't fix it unprompted — list it in the summary as something the next review would likely flag, and let the user decide before the push.

## Push and post — only after everything is handled

Do not push anything until every comment has been handled and the re-review pass is done. Then:

1. Show the summary (below) including every queued reply verbatim.
2. Ask before pushing. On approval: `git push` (plain — never force push, never rebase, never amend commits that aren't from this run).
3. After the push succeeds, post the queued replies to their threads.

If the user wants a reply reworded, fix it before posting.

## Final summary

A table: comment number, author, what was done (fixed / pushed back / spec / asked), and the commit hash if there is one. After the table, list anything unrelated noticed along the way but deliberately left alone.

## Hard constraints

- Never resolve a review thread on the reviewer's behalf — that's their call.
- Never close or merge the PR.
- Never stash, discard, force-push, rebase, or amend other people's commits.
- If a comment's target line no longer exists, say so in the reply rather than guessing.
- About to do anything destructive: stop and ask.
