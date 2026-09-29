---
name: screenshots
description: "Screenshot the current PR's user-facing changes in headless Chrome on FAKE test data, annotate each image with circles or boxes, numbered badges, arrows and callout cards plus a header band (PR, branch, date, test-data flag), with every detail drawn INTO the image, and publish them on one claude.ai artifact page with Copy image buttons for pasting anywhere. For Rails apps with RSpec, Capybara and Selenium Chrome (built on Ambiki)."
argument-hint: "[PR number, or the pages/changes to focus on]"
---

# /screenshots

Produce annotated screenshots of what this PR changed, and one private claude.ai artifact link where Jason can copy each image and paste it anywhere (a PR description, Slack, a doc, an email).

**The one rule that shapes everything: every piece of information lives INSIDE the image.** The header band carries the PR, the page, what the shot shows, the branch, the date and the test-data flag; the numbered callout cards carry what each highlight is and why it matters. The artifact page adds nothing a reader needs: just a title, the images and their copy buttons. An image pasted on its own must explain itself.

Work without asking questions. If `$ARGUMENTS` names a PR number or specific pages/changes, focus there; otherwise cover the current branch's PR.

## Tools in this folder

| File | What it is |
|---|---|
| `harness.rb` | Ruby module `ScreenshotHarness` for a throwaway feature spec: `capture_annotated(...)` fits the viewport to the page, measures the highlight targets, saves the raw shot through Chrome's own screenshot command, and queues the annotation; after the scenario it composes every queued shot into its final PNG. |
| `compose.html` | The annotator the harness opens around each raw shot: header band, highlight shapes with white halos, numbered badges (reading order), callout cards in a right gutter, arrows. Drawn outside the app, so app CSS cannot hide or shift anything. |
| `example_spec.rb` | Starter for the throwaway spec. |
| `page_template.html` | The artifact page: title, images, Copy image buttons (clipboard with a right-click fallback), both themes. |

## Ground rules

- **Fake data only.** Build every record with the project's factories in the TEST database, through a throwaway feature spec. Never point anything at the dev or production database, never use a real patient, never run the dev server or a Rails console for this. Every image says "Test data · no real patients" in its header.
- **Honor the repo's test isolation.** If CLAUDE.md or memory names a test-database setting (Ambiki: `DISABLE_SPRING=1 TEST_ENV_NUMBER=7 RAILS_ENV=test`), run the spec with it.
- **Change no application code.** The only file written in the repo is the throwaway spec, named `spec/features/__screenshots_<slug>_spec.rb`; it is never staged or committed, and it is deleted before you finish.
- **Plain words in the images.** Callout labels six words or fewer, notes one or two short sentences, from the user's side of the screen. No em dashes.

## Steps

### 1. Scope the PR

```bash
gh pr view ${PR:-} --json number,title,body,headRefName,baseRefName,url
git log --oneline "$(git merge-base HEAD origin/<base>)"..HEAD
git diff --stat "$(git merge-base HEAD origin/<base>)"..HEAD -- app/views app/javascript app/helpers app/components
```

From the PR body, the commit subjects and the view/JS/CSS/helper diffs, list the **visible** changes: new cards, panels, buttons, columns, badges, states, messages, layout. Skip what has no screen (jobs, services, migrations) unless it changes what a page shows.

Plan 3 to 8 shots. For each: the page and the state it needs (records, flags, permissions, anything clicked open), the region to crop to, and one highlight per distinct change with its label and note. Print the shot list in a short block, then build it.

### 2. Write the throwaway spec

Copy `example_spec.rb` to `spec/features/__screenshots_<slug>_spec.rb` (one file can hold every shot; split by page if that reads better) and fill it in:

- `require File.expand_path('~/.claude/skills/screenshots/harness')`, `include ScreenshotHarness`, `loader('browser')`, and `js: true, browser_ci: true` on the feature.
- `out_dir`: the session scratchpad directory from the system prompt plus `screenshots/<branch>/`; with no scratchpad, the repo's `tmp/screenshots/<branch>/` (gitignored).
- `details`: `['Branch <branch>', '<Mon D, YYYY>', 'Test data · no real patients']`.
- Records that make the page look lived in: realistic text, dates relative to today, enough rows for lists and charts. Enable the flags the change sits behind and `user.permit!` what the page needs. Sign in with `login_as(user, scope: :user)`.
- Before each capture, wait for something only the finished page shows (`expect(page).to have_text(...)`), then `sleep 1` for charts.
- Collapse what is not the change (expanded sub-rows, open panels) before capturing, so the image stays short and on topic.

`capture_annotated` options:

| Option | Meaning |
|---|---|
| `name` | file stem, numbered for order: `01-documents-card` |
| `title` | header title: `PR #7650 · Goal page: the Documents card` |
| `subtitle` | one sentence: what the shot shows |
| `details` | header pills (branch, date, test-data flag; any pill containing "Test data" is drawn yellow) |
| `clip` | `{ selectors: ['CSS', { xpath: '...' }, ...], margin: 20 }` crops to those elements (taken whole) plus a margin that fades out toward the edges, so whatever the crop cuts through reads as context; `{ rect: { x:, y:, w:, h: } }` for an exact region (no fade); omit for the whole page |
| `highlights` | each `{ selector: }`, `{ xpath: }` or `{ text: }` (an element whose own text contains it), with `index:` (nth match), `within:` (CSS scope for xpath/text), `all: true` (box every match together), `fit: :box` (frame the element's own box, see below), `shape:` (`:box` default, `:circle`, `:none` for an arrow only), `pad:` (px, default 6), `label:`, `note:`, `arrow: false` (shape and badge, no card) |
| `width` | page width to render at (default 1440) |

Choosing targets:
- Crop to the card or panel that changed (`.card:has(<something unique inside>)`), never a whole long page unless the change IS the page. Take whole cards and their headings (an `{ xpath: }` entry reaches a heading with no hook), so nothing a reader needs sits in the fading margin.
- `.card:has(X)` matches the OUTERMOST card first when cards nest (a document card holding goal cards); scope it with a hook the inner card has, like `[data-controller="..."]:has(X)`.
- Prefer stable hooks: `data-*` attributes, ids, component classes. For table rows by text: `//tr[td[contains(., 'Row text')]]`.
- `all: true` boxes a run of siblings that has no wrapper (sub-rows, three timeline entries); an XPath union (`//a | //b`) with `all: true` boxes unrelated elements together.
- Boxes hug what a block element shows (its children and text, not its padding); badges, pills, icons, form controls and `fit: :box` targets use the element's own box. Stacked boxes give back padding so they do not touch, and never cross the text they frame. Use `fit: :box` on a short line of text when a full-width box keeps its arrow out of a chart or table.
- Badges and cards share one reading order (row by row, left to right within a row), so card 1 is the top card. Give each row at most one arrowed highlight: two on one line make the arrows cross, so box the row and put the second fact in its note.
- Boxes for areas and rows, circles for small controls (icons, chevrons). Badges hang off a box's left edge, clear of the labels above a field.

The harness fails loudly when a target is missing or falls outside the crop. Fix the selector; never drop the highlight quietly.

### 3. Run it

```bash
DISABLE_SPRING=1 TEST_ENV_NUMBER=7 RAILS_ENV=test bundle exec rspec spec/features/__screenshots_<slug>_spec.rb > <out_dir>/run.txt 2>&1
```

(Use the repo's own isolation settings; the ones above are Ambiki's. If bundler rejects the Ruby version, load the repo's Ruby first: `source ~/.rvm/scripts/rvm && rvm use "$(cat .ruby-version)"` under rvm.) Selenium Manager fetches chromedriver on its own; test packs compile on demand, and an unstyled page means they need compiling. Each shot leaves `<name>.png` (final), `<name>.raw.png` and `<name>.compose.html` in `out_dir`.

### 4. Look at every final image once

Open each final PNG with the Read tool. Check: every shape sits on its target, every arrow lands, card text is complete and legible, the crop shows the change with enough context, no header or card is cut off. Fix and re-run once; do not loop.

### 5. Publish the artifact

1. New artifact for this branch: call the Artifact tool with `action: "quickstart"`, `intent: "other"` first (once per new artifact). Re-run for a branch that already has one (`<out_dir>/artifact_url.txt` exists): skip quickstart and update that URL instead.
2. Copy `page_template.html` to `<out_dir>/index.html`. Replace the `{{TITLE}}` placeholder (both places) with `PR <number> Screenshots`, and the `{{FIGURES}}` placeholder with one `<figure>` per final PNG in order, exactly as the template's comment shows (`1 of N` count, a `Copy image` button with `data-copy="img/<name>.png"`, the `<img>` with its real width and height and the image's header title as `alt`). Add no captions or notes: the images carry them.
3. Publish: `file_path: <out_dir>/index.html`, `files: { "img/<name>.png": "<out_dir>/<name>.png", ... }` (finals only, never the `.raw.png`), `icon: "image"`, `description: "Annotated screenshots of PR <number>'s changes: <few words>, on test data."`. For an update, pass `url` from `artifact_url.txt`, send the new and changed images, and `null` for images that no longer exist.
4. Save the artifact URL to `<out_dir>/artifact_url.txt`.

### 6. Clean up

```bash
rm spec/features/__screenshots_*_spec.rb
git status --short
```

No tracked file may have changed, and no new file may remain in the repo. The images stay in `out_dir` only.

### 7. Report

The artifact link, then one line per image (its header title). Say that the artifact is private until Jason shares it from the page's Share menu, and that everything shown is test data.
