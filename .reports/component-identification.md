# gnome-calendar-rb — component identification

This document enumerates upstream `gnome-calendar`'s components (type, CSS
classes, signals/actions, owner file) on both sides, per the
`component-identification` skill. It is the raw inventory that
`component-parity.md` compares against.

## Where the enumeration already lives

`.reports/component-inventory.md` (committed before this audit, `git log`
shows it at `9e76db67 Inventory upstream components`) already performs the
file-level half of this job: it lists all 93 upstream `.c` + 96 `.h` files
under `src/`, the 46 blueprint files, the 1 GSettings schema, the 9 GResource
manifests, and maps every one of the 62 user-facing components and 28
supporting files to its `lib/<thing>.rb` target, marking presence. That
document is accurate as far as it goes and this audit re-verifies its file
list against `git ls-tree -r --name-only origin/main` and `ls lib/` — the
counts match (93 `.c`, 96 `.h`, 46 `.blp`, 38 files under `lib/` on `ruby`).

**What that document does not do, and what component-identification actually
requires:** it identifies components by file-pair only. It does not descend
into any individual file to enumerate the five facets the skill requires
(type, CSS classes, signals, actions, owner) widget by widget. For the files
marked present, nobody has written down upstream's per-widget inventory to
check the port's widgets against — only "window.rb exists" is recorded, not
"window.rb must contain this exact list of widgets."

## Per-widget identification performed in this pass

For the port's 20 present user-facing components, this pass spot-checked
three load-bearing files against upstream's blueprint/`.c` source line by
line (the sample used for `component-parity.md`): `gcal-window.blp`/`.c` →
`lib/window.rb`, `gcal-event-widget.blp`/`.c` → `lib/event_widget.rb`, and
`gcal-month-cell.blp`/`.c` → `lib/month_cell.rb`. Findings are reported in
`component-parity.md`; the headline one is that `lib/event_widget.rb`'s
`build` method is invoked twice on the same instance in the popover/agenda
path, because nothing memoizes against rebuild, and GTK's own assertion
(`gtk_box_append: assertion 'gtk_widget_get_parent (child) == NULL' failed`)
fires live during the drive run (see `.reports/test-parity.md`) — a component
identity bug no static read would have caught as cleanly as the runtime
check did.

The remaining 17 present files were not opened widget-by-widget in this pass;
their component-level identity (CSS classes, exact signal set) is therefore
**unverified**, not confirmed. Full identification would require going
through each file the way the three samples were.

## Reverified this round

Current HEAD is `ed5e9f43`, two commits past this document's prior count.
`lib/global.rb` and `lib/event_widget_pool.rb` now exist (ported in
`ed5e9f43`); both are supporting files, so the 42/62 user-facing gap below
is unchanged and the supporting-file gap narrows from 12/28 to 10/28. The
event-widget double-`build` defect flagged below was the specific thing
`event_widget_pool.rb` was written to fix — this round's rerun of the drive
script confirms it still fires identically (see `.reports/component-parity.md`
and `.reports/test-parity.md`), so `event_widget_pool.rb` existing is not
evidence the identification finding below is closed.

## Components present upstream with zero file created on `ruby`

42 of 62 user-facing components and 10 of 28 supporting files have no
corresponding `lib/*.rb` file at all, so there is nothing to identify on the
port side for them: `calendar_combo_row`, `month_view_row`, `week_view`,
`week_header`, `week_grid`, `week_hour_bar`,
`search_button`, `calendar_navigation_button`, `weather_settings`,
`drop_overlay`, `fading_label`, `overflow_bin`, `bidi`, the entire
event-editor directory (19 files), the entire calendar-management directory
(7 files), the entire importer directory (3 files), `source_discoverer`,
`calendar_monitor`, `timeline`, `timeline_subscriber`, `time_zone_monitor`,
`shell_search_provider`, `search_engine`, `search_model`, `search_hit`,
`search_hit_event`, `weather_service`, `weather_info`, `gui_utils`. These are
not partially-identified; they are wholly absent. See
`.reports/component-parity.md` for what each one means functionally.

## Gap

Component identification on the Ruby side is incomplete below the file
level for the 20 files that exist, and nonexistent for the 42 user-facing
components and 12 supporting files that were never created. I did not do the
full per-widget identification for every present file in the time this audit
took; three samples is not full coverage, and I am reporting that
incompleteness rather than extrapolating a pass from three files.
