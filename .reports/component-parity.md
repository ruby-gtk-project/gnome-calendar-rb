# gnome-calendar-rb — component parity

Per the `component-parity` skill: parity requires the same widget type, in
the same number, with the same CSS classes, responding to the same
signals/actions, and showing the same translatable strings — all four axes,
per component. This report is adversarial: it is scoped to find gaps, not to
confirm the port.

## Headline number

**21 of 62 user-facing components exist on `ruby`, as of HEAD `ba3a6af5`
(one commit past `ed5e9f43`, adding `lib/calendar_navigation_button.rb`).
41 do not exist at all.** 18 of 28 supporting files exist; 10 do not —
unchanged this round, since the new file is user-facing, not supporting.
Re-verified this pass against `git ls-tree -r --name-only origin/main` and
`ls lib/` on `ruby`: 93 `.c`, 96 `.h`, 46 `.blp` upstream; 43 files in `lib/`
on the port. A component with no file cannot have parity on any axis —
count parity alone is 21/62 = 34% for user-facing components, before style,
behaviour or text are even considered.

Note: `.reports/component-inventory.md` line 140 still marks
`gcal-calendar-navigation-button.c/.h`+`.blp` as **no** — that line is
stale as of this HEAD and should not be trusted over `ls lib/`; see
`.reports/accountability-ensurance.md` Finding 5.

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

`lib/calendar_navigation_button.rb` (new this round) was not spot-checked
line-by-line against `gcal-calendar-navigation-button.c`/`.blp` in this
pass — it is counted as present because the file exists and the drive
script's new checks (active in month view, swaps to a static heading in
agenda view) pass, but that is two behavioural assertions, not a four-axis
check. Treat it the same as the other 17 unchecked presents below: existing
and passing its own narrow test, not independently verified.

## Confirmed behavioural bug in a component marked "present" — still reproduces after the supposed fix landed

`ed5e9f43` ("Port gcal-global.c and gcal-event-widget-pool.c") added
`lib/event_widget_pool.rb` specifically to reuse `EventWidget` instances
"across rebuilds instead of discarding and recreating them" and wired it
into `MonthCell`, `MonthPopover` and `AgendaViewDayRow` — exactly the three
call sites implicated in the double-`build` bug this report first found.
This pass **reran the drive script against the current `ruby` HEAD
(`ed5e9f43`) specifically to check whether that fix closed the gap. It did
not.** The identical `Gtk-CRITICAL` fires the identical four times, from the
identical origin:

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

## Additional runtime noise this pass found, that was not in the prior report

The same rerun (`ed5e9f43`, full stderr captured this time, not just
grepped for the one known assertion) surfaces three more problems the 121
`check()` calls do not look for:

- **`Gtk-CRITICAL **: New application windows must be added after the
  GApplication::startup signal has been emitted.`** — fires twice during
  the run. A window is being constructed/added before `startup` completes
  somewhere in the drive sequence (likely a second `Window.new` the script
  creates to test multi-instance behaviour at step 53, "the window is still
  the only toplevel at the end of the run" — but that step passes, so the
  critical is silently tolerated rather than caught).
- **Dozens of `Adwaita-WARNING **: AdwToastOverlay ... exceeds
  AdwApplicationWindow width/size`** — the toast overlay repeatedly requests
  more width/size than the window provides, through most of the run. This
  is a real layout defect (something is giving the toast overlay a fixed or
  unclamped size request) that would be visible on screen as either clipped
  toasts or an oversized window, and nothing checks for it.
- **`Gtk-WARNING **: Finalizing GtkButton ..., but it still has children
  left: - GtkPopover ...`** at the end of the run — a button is being
  destroyed while still parenting a popover, meaning something is not
  unparenting the popover before the button that owns it goes away. This is
  a resource-lifecycle bug, not cosmetic; in a long-running app process
  (not, how this drive script exits) it is the shape of a leak.

None of these three are mentioned in `.reports/accountability-ensurance.md`
or `.reports/test-parity.md` as previously written, because the prior pass
only grepped for the one known `gtk_box_append` assertion rather than
reading the whole stderr stream. They are real defects in components the
inventory marks "present," found only by actually running the app and
reading everything it printed, which is the finding `component-parity`'s
Step 4/5 exists to force.

## Three further FAILs the drive script itself reports

The driver run on this pass (reran twice at current HEAD `ba3a6af5`, same
result both times) printed:

```
126 of 129 checks passed
  failed check: the narrow switcher is in the bin
  failed check: the main window never collapsed
  failed check: its navigation is still showing
DRIVE FAILED (3)
```

These are the identical three failures this report has now found across
three audit rounds and three different HEADs (`ed5e9f43` → `ed5e9f43` →
`ba3a6af5`); the check count grew from 121 to 129 but the failing set did
not change. The task brief for this round again claimed `drive_ok=true,
129 checks passed, 0 failed` — false, reproducibly. See
`.reports/accountability-ensurance.md` and `.reports/test-parity.md`.

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

- 41/62 user-facing components and 10/28 supporting files: absent outright
  (user-facing gap narrowed from 42 to 41 this round by
  `calendar_navigation_button.rb` landing, unchecked against upstream
  source beyond the drive script's two new assertions).
- 1 confirmed functional defect in a "present" component (`event_widget.rb`
  double-build / GTK assertion failure), surfaced only by actually running
  the app, not by reading the code, and **confirmed still present after a
  commit that was specifically written to fix it**.
- 3 new runtime defects (two `GApplication::startup` criticals, repeated
  `AdwToastOverlay` oversize warnings, one `GtkButton` finalized-with-child
  warning) found this round by reading the whole stderr stream instead of
  grepping for the one previously-known assertion.
- 3 confirmed behavioural failures in `window.rb`'s breakpoint handling,
  reported by the port's own drive script.
- 17 of 20 present components: not checked against upstream source in this
  pass: style and text axes unverified.

No full component passes all four axes with independent verification in
this report. `clean: true` is not supportable from this evidence.
