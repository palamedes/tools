---
name: research
description: "Deep-dive investigation of an Asana ticket — find the root cause, search for related issues, and propose multiple solutions."
argument-hint: <asana-ticket-url>
allowed-tools:
  - "mcp__asana__asana_get_task"
  - "mcp__asana__asana_get_task_stories"
  - "mcp__asana__asana_search_tasks"
  - "mcp__asana__asana_get_tags_for_task"
  - "mcp__asana__asana_get_project"
  - "mcp__asana__asana_create_task_story"
  - "Agent"
  - "Grep"
  - "Glob"
  - "Read"
  - "Bash"
---

Deep-dive investigation of an Asana ticket. Find the root cause, search for prior/related work, and propose multiple solutions.

## Argument Validation

- If `$ARGUMENTS` contains an Asana URL, extract the task ID and use it.
- If `$ARGUMENTS` is empty, check whether an Asana ticket was already loaded earlier in this conversation (via `/asana`). If so, use that ticket — do not re-fetch it, just reference the already-loaded context.
- If neither an argument nor a previously loaded ticket exists, stop and ask:
  > No ticket loaded. Either pass a URL (`/research https://app.asana.com/...`) or load one first with `/asana <url>`.

## Phase 1: Gather Context

### 1a. Load the ticket

Extract the task ID from the URL (last numeric segment) and fetch the full task from Asana. Collect:
- Task name, description, assignee, due date, status, project, tags
- All comments/stories on the task (these often contain reproduction steps, screenshots, error messages, and context that isn't in the description)

Summarize the ticket clearly before proceeding.

### 1b. Search for related Asana tickets

Using keywords, tags, and phrases from the ticket, search Asana for:
- **Duplicate tickets** — same problem reported before
- **Adjacent tickets** — related features, similar symptoms, same area of the app
- **Previously resolved tickets** — same or similar issue that was already fixed (check completed tasks too)

Run at least 2-3 different search queries using different keyword combinations to cast a wide net. For each result, note:
- Task name, status (open/completed), assignee, URL
- Whether it was resolved and how (read comments if needed)

Report what you found: duplicates, prior fixes, related work in progress.

## Phase 2: Codebase Investigation

This is the deep dive. Be thorough — the goal is to fully understand the problem before proposing solutions.

### 2a. Identify the affected area

From the ticket description, comments, and any error messages, determine:
- Which models, controllers, services, views, or jobs are involved
- Which user flows are affected
- Whether this is a data issue, logic bug, UI problem, permission gap, or missing feature

### 2b. Read the relevant code

- Use Grep and Glob to find the relevant files
- **Read files in full** — don't just look at snippets. Context matters.
- Follow the call chain: controller -> service -> model -> view
- Check for related specs that might reveal intended behavior
- Look at git history for recent changes to the affected files: `git log --oneline -20 -- <file>`
- If a recent change looks relevant, read the full diff: `git show <sha> -- <file>`

### 2c. Reproduce the logic mentally

Walk through the code path step by step. Trace what happens when a user triggers the reported behavior. Identify where the logic breaks down or where the gap exists.

### 2d. Check for edge cases

- Soft deletion: are deleted records leaking through?
- Permissions: is the ability file missing a `can` declaration?
- Timezone: is `Date.today` used instead of `Date.current`?
- Nil safety: can any association or attribute be nil in this path?
- Race conditions: can concurrent requests cause issues?
- Feature flags: is something gated behind a Flipper flag the user doesn't have?

## Phase 3: Report

Present findings in this structure:

### Ticket Summary
One paragraph summarizing what the ticket is about.

### Related Asana Tickets
Table of related/duplicate/previously-resolved tickets found:

```
| Task | Status | Relevance | URL |
|------|--------|-----------|-----|
```

If a prior ticket resolved the same issue, highlight it and explain what was done.

### Root Cause Analysis
Clear explanation of what is causing the problem. Include:
- The specific file(s) and line(s) where the issue originates
- A step-by-step trace of the failing code path
- Why it fails (the logic error, missing condition, data issue, etc.)

If you cannot determine a definitive root cause, say so and explain what you've ruled out.

### Proposed Solutions

Present **multiple solutions** when possible, ordered by recommendation:

```
#### Solution 1: [Name] (Recommended)
**Approach:** What to change and why.
**Files to modify:** List of files with specific changes.
**Pros:** Why this is the best option.
**Cons:** Any downsides or risks.
**Effort:** Low / Medium / High

#### Solution 2: [Name]
...
```

For each solution:
- Be specific — name the files, methods, and lines to change
- Explain the tradeoffs
- Note if it needs a migration, feature flag, or spec updates
- Flag if it touches high-risk areas (ledger, billing, permissions)

### Recommendations
- Which solution you recommend and why
- Whether specs exist or need to be written
- Whether this should be behind a feature flag
- Any related tickets that should be updated or closed if this is fixed

## Phase 4: Asana Follow-Up

After presenting the full report, ask:

> Would you like me to post these findings as a comment on the Asana ticket?
> 1. **Post full findings** — root cause, related tickets, and recommended solution
> 2. **Post summary only** — condensed version with root cause and recommendation
> 3. **Skip** — keep findings in this conversation only

If the user chooses to post, draft the comment and show a preview first. Format the comment using `html_text` with clear sections (Root Cause, Related Tickets, Recommended Fix). Use literal newlines, not escaped `\n`. Wait for the user to confirm before posting.

## Ground Rules

1. **Be thorough.** This is a deep dive, not a quick glance. Read full files, follow call chains, check git history.
2. **Cite everything.** Every claim about the code must reference a specific file and line.
3. **Don't guess.** If you're unsure about something, say so. Investigate further or flag it as uncertain.
4. **Don't fix anything.** This is research only — no code changes, no commits, no PRs. Just analysis and proposals.
5. **Surface surprises.** If you find something unexpected (inconsistent behavior, dead code, potential bugs beyond the ticket scope), mention it briefly.
6. **Use subagents for parallel investigation.** When you need to search multiple areas of the codebase simultaneously, spawn Explore agents to parallelize the work.
