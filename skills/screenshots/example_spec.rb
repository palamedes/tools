# Starter for a /screenshots throwaway spec. Copy it to
# spec/features/__screenshots_<slug>_spec.rb in the repo, fill it in, run it,
# then DELETE it. Never commit it. Fake data only: factories, test database.
require 'rails_helper'
require File.expand_path('~/.claude/skills/screenshots/harness')
loader('browser')

RSpec.feature 'Screenshots: <what the shots show>', js: true, browser_ci: true do
  include ScreenshotHarness

  let(:out_dir) { '<scratchpad>/screenshots/<branch>' }
  let(:details) { ['Branch <branch>', '<Mon D, YYYY>', 'Test data · no real patients'] }
  let(:user)    { create(:user, :with_credentials_ccc_slp_with_org, :with_professional_plan) }
  let(:org)     { user.current_org }
  let(:patient) { create(:patient, organization: org) }

  scenario 'the shots' do
    Flipper.enable(:some_flag, org)     # every flag the change sits behind
    user.permit! :indexAllOrgPatients   # and every permission the page needs

    # Build the records the page shows: realistic words, dates relative to today
    # (10.weeks.ago, 1.day.ago), enough rows that lists and charts look lived in.

    login_as(user, scope: :user)
    visit '/the/page'
    expect(page).to have_text('Something only the finished page shows')
    sleep 1 # let charts and transitions settle

    capture_annotated(
      name: '01-short-slug', out_dir: out_dir, details: details,
      title: 'PR #1234 · Page name: the change',
      subtitle: 'One plain sentence on what this shot shows.',
      clip: { selectors: [{ xpath: "//h2[normalize-space(.)='Section heading']" }, '.card:has(.the-part-that-changed)'], margin: 20 },
      highlights: [
        { selector: '.the-new-thing', shape: :box,
          label: 'Six words at most', note: 'One or two plain sentences on what changed and why it matters.' },
        { xpath: "//tr[td[contains(., 'Row text')]]", all: true, shape: :box, pad: 3,
          label: 'Some table rows', note: 'all: true boxes every match together, for a run of rows with no wrapper.' },
        { text: 'Visible label text', shape: :circle,
          label: 'A small control', note: 'Circles suit small targets; boxes suit areas and rows.' }
      ]
    )

    # Another shot: change the page state (click, open a panel, visit another
    # page), then call capture_annotated again. Annotation happens after the
    # scenario, so the page stays live between shots.
  end
end
