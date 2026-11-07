# gnome-calendar-rb — component parity

Per the `component-parity` skill: parity requires the same widget type, in
the same number, with the same CSS classes, responding to the same
signals/actions, and showing the same translatable strings — all four axes,
per component. This report is adversarial: it is scoped to find gaps, not to
confirm the port.

## Headline number

**20 of 62 user-facing components exist on `ruby`. 42 do not exist at all.**
16 of 28 supporting files exist; 12 do not. These counts come from
`.reports/component-inventory.md`, re-verified in this pass against
`git ls-tree -r --name-only origin/main` and `ls lib/` on `ruby`: both counts
check out exactly (93 `.c`, 96 `.h`, 46 `.blp` upstream; 38 files in `lib/`
on the port). A component with no file cannot have parity on any axis —
count parity alone is 20/62 = 32%, before style, behaviour or text are even
considered.

Whole subsystems are 0% ported:
- **Event editor** (19 files: `event-editor/`): 0 of 19. The port can create
  an event through quick-add but cannot edit one, set a location, add
  attendees, set reminders, add notes, or set a time zone. `event_popover.rb`
  exists but its "action button closes the popover (no editor wired yet)"
  per the drive script's own step 10 comment — it does not open an editor
  because there is no editor to open.
- **Calendar management** (7 files): 0 of 7. No way to add/edit/remove a
  calendar source, no online-accounts page, no new-local-calendar page.
  `win.open-online-accounts` exists as an *installed action* (drive step
  32–33 confirms the action exists) but nothing proves what it does when
  activated beyond existing.
- **Importer** (3 files) and `drop_overlay`: 0 of 4. Dragging an `.ics` file
  onto the window, or opening one from the file manager, has no destination
  component.
- **Search** (6 files: `search_button` + 5 `search/` files) and
  `shell_search_provider`: 0 of 7. `app.search` is listed in
  `component-inventory.md`'s expected app actions but there is no
  `lib/search_*.rb` to back it.
- **Weather** (3 files): 0 of 3.
- **Week view** (4 files: `week_view`, `week_header`, `week_grid`,
  `week_hour_bar`): 0 of 4. The month/agenda/week switcher the drive script
  exercises (`win.change-view`) has a week destination with nothing behind
  it — `component-inventory.md` itself notes "This fills the one empty page
  in the window's view stack" is still future work.

## Confirmed behavioural bug in a component marked "present"

`lib/event_widget.rb` is marked `✓` in the inventory, and it does build and
is visually shown by the drive run. But running it (`nix develop --command
xvfb-run -a ruby test/drive_gnome_calendar.rb`) throws, four times in a row,
during the exact step that shows an event popover from the agenda view
(step 8, "clicking the event in the agenda opens the event popover"):

```
Gtk-CRITICAL **: gtk_box_append: assertion 'gtk_widget_get_parent (child) == NULL' failed
	from .../lib/event_widget.rb:37:in 'block (2 levels) in EventWidget#build'
	...
	from .../lib/window.rb:560:in 'Window#show_event'
```

`EventWidget#build` appends the same memoized child widgets to a box a
second time once the widget is reused for a second event/location, because
nothing guards `build` against being called more than once on the same
instance (the memoized-accessor house style assumes `build` runs exactly
once; `show_event` calls `.widget` — which calls `build` — on what turns out
to already be a built instance in this path). GTK's own assertion catches
it; the drive script's checks do not, because none of them assert "no
Gtk-CRITICAL was emitted", so this is a real defect in a component the
inventory marks done, surviving the driver's own notion of green. See
`.reports/test-parity.md` for the exact drive-run numbers.

## Three further FAILs the drive script itself reports

The driver run on this pass printed:

```
118 of 121 checks passed
  failed check: the narrow switcher is in the bin
  failed check: the main window never collapsed
  failed check: its navigation is still showing
DRIVE FAILED (3)
```

These are breakpoint-collapse behaviours in `lib/window.rb` (steps 35 and
38 of the drive script) — the narrow-width switcher does not end up in the
bin it is supposed to move into, and the wide window's collapse state is not
independent of the narrow one, meaning the breakpoint state is leaking
between the two window instances the step creates. This is a component
behaviour (axis 3, "responds to the same signals/actions") that the port's
own test disproves, not something this audit had to go looking for.

## Spot-checked components (3 of 20 present, read against upstream source)

- **`lib/window.rb` vs `gcal-window.blp`+`.c`**: broad structural match
  (toolbar view, split view, header bars, shortcut controller) confirmed by
  the drive script's accelerator and action checks (steps 32–33 pass). Not
  independently verified against every CSS class upstream applies
  conditionally (e.g. `drop-target` on `split_view` during a drag) — the
  importer/drop-overlay absence means that CSS class is structurally unused
  in the port regardless of whether `window.rb` defines it.
- **`lib/month_cell.rb`**: overflow behaviour matches upstream's intent per
  drive steps 19–24 (3 events fit, a 4th overflows, the popover lists all 4).
  No independent check that the cell's CSS classes (`.day-cell`,
  `.different-month`, etc.) are all present — not verified either way in
  this pass.
- **`lib/event_widget.rb`**: see the confirmed bug above. This is axis 3
  (behaviour) failing in a way a static read would not show.

## What "20 present" does not mean

Per the skill: "count" is the floor, not the proof. Of the 20 present
components, only 3 got even a partial check against upstream source in this
pass, and one of those 3 has a confirmed runtime defect. The other 17
presents are **unverified on three of the four axes** (style, full
behaviour, text) — their presence in `lib/` is not evidence of parity, only
evidence of existence. I am not extrapolating "probably fine" from the three
samples; the honest status for those 17 is "not checked."

## Gap summary

- 42/62 user-facing components and 12/28 supporting files: absent outright.
- 1 confirmed functional defect in a "present" component (`event_widget.rb`
  double-build / GTK assertion failure), surfaced only by actually running
  the app, not by reading the code.
- 3 confirmed behavioural failures in `window.rb`'s breakpoint handling,
  reported by the port's own drive script.
- 17 of 20 present components: not checked against upstream source in this
  pass: style and text axes unverified.

No full component passes all four axes with independent verification in
this report. `clean: true` is not supportable from this evidence.
