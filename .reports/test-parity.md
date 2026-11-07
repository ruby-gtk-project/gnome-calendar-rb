# gnome-calendar-rb — test parity

Per the `test-parity` skill: parity requires an exact bijective census
between upstream's tests and the port's, not a vibe that "there's a test
suite."

## Upstream test census

`git ls-tree -r --name-only origin/main` under `tests/` lists:

```
tests/calendar.ics
tests/gcal-simple-server.c / .h
tests/gcal-stub-calendar.c / .h
tests/meson.build
tests/test-daylight-saving.c
tests/test-discoverer.c
tests/test-event-attendee.c
tests/test-event-list.c
tests/test-event.c
tests/test-internals.c
tests/test-range-tree.c
tests/test-range.c
tests/test-server.c
tests/test-utils.c
```

9 real test files (`test-*.c`), each a GLib test suite with multiple
`g_test_add_func` cases — e.g. `test-range.c` alone defines `range_new`,
plus (per upstream's convention) several more range/overlap/contains cases.
No per-test-case count was taken file by file in this pass (that full
census is the next unit of work this report calls for) but the file-level
count is unambiguous: **9 upstream test files, each with multiple cases —
call it dozens of individual test cases at minimum.**

## Port test census

`find test spec -name "*.rb"`:

```
spec/spec_helper.rb   — harness config only, zero spec files, zero `it` blocks
test/drive_gnome_calendar.rb  — a UI driver, not an RSpec/Minitest suite
test/gtk_driver.rb            — the driver's harness code
```

`find . -name "*_spec.rb"` returns **nothing**. There is no RSpec suite.
`spec/README.md` documents how to write one; none has been written. The
port's actual commit history (`git log --oneline`) shows no commit that adds
a `_spec.rb` file.

**Bijection result: 0 of 9 upstream test files have any named Ruby
counterpart. The census is not "incomplete", it is empty.** None of
`test-daylight-saving.c`, `test-discoverer.c`, `test-event-attendee.c`,
`test-event-list.c`, `test-event.c`, `test-internals.c`,
`test-range-tree.c`, `test-range.c`, or `test-utils.c` has a ported test
anywhere in this repository, named or unnamed.

## What exists instead, and why it is not a substitute

`test/drive_gnome_calendar.rb` is a headless UI driver (121 `check()` calls
across 53 numbered steps) that both exercises the widget tree and, inline,
asserts a handful of model-level properties — e.g. step 49 ("CalendarRange
overlap and contains? agree with upstream's cases"), step 50
("RangeTree finds and removes what was added"), step 51
("Utils helpers answer upstream's values"), step 52 ("Event comparisons
and formatting follow upstream's rules"). These do map, loosely, onto
`test-range.c`, `test-range-tree.c`, `test-utils.c`, and `test-event.c` by
subject matter — but:

1. They are **not named by upstream test case**. "CalendarRange overlap and
   contains? agree with upstream's cases" is one `check()` covering what
   upstream's `test-range.c` splits across several named functions
   (`range_new`, and others not inspected case-by-case here). This is an
   N-to-1 collapse, which the skill explicitly calls a parity failure
   wearing a disguise, not a bijection.
2. They prove nothing about `test-daylight-saving.c`, `test-discoverer.c`,
   `test-event-attendee.c`, `test-event-list.c`, `test-internals.c`, or
   `test-server.c`/`gcal-simple-server.c`/`gcal-stub-calendar.c` (the
   EDS/online-accounts discovery and server-stub tests) at all. Zero
   coverage, not degraded coverage.
3. They are comments in a file's header describing intent
   ("The spec suite (empty so far — run through RSpec per the dev-shell
   banner) covers the display-free half, were there any non-widget units
   isolated enough to need no widget at all") — the file's own author
   admits in writing that the RSpec suite is empty. This is the honest
   version of the gap; it should not be read as closing it.

## Running the suite that exists

Ran it for real, per the task's mandatory runtime instructions:

```
nix develop --command xvfb-run -a ruby test/drive_gnome_calendar.rb
```

Result: **118 of 121 checks passed, 3 failed, "DRIVE FAILED (3)"**. This
contradicts the runtime gate this audit was handed (`drive_ok=true, 121
checks passed, 0 failed`) — that claim does not hold under an actual rerun
in this session, on this checkout, right now. The three failures:

**Rerun again for this round**, at current HEAD `ed5e9f43` (two more
commits landed since the last time this file was written: an inventory
update and `global.rb`/`event_widget_pool.rb`), because this round's task
brief repeats the same claim with different cosmetic numbers:
`drive_ok=true, 121 checks passed, 0 failed, covering 39 components`.
**Same result, same three failures, same count of 121, still 3 failed.**
Two things are worth flagging about that specific repetition: (1) the
check count did not change (121 both rounds) despite the brief's own
"components covered" figure moving from 26 to 39, which is itself odd if
the component count genuinely drove the check count; and (2) the false
"0 failed" claim was handed to this audit a second time, after the first
audit already reported it false and in writing. Whatever produces this
gate value is not reading the last audit's output, or is not rerunning the
script at all. The three failures, unchanged:

```
failed check: the narrow switcher is in the bin
failed check: the main window never collapsed
failed check: its navigation is still showing
```

All three are in the breakpoint-collapse behaviour of `lib/window.rb`
(drive steps 35 and 38). Additionally, the run emits a `Gtk-CRITICAL`
assertion failure (`gtk_box_append: assertion 'gtk_widget_get_parent (child)
== NULL' failed`) four times, originating in `lib/event_widget.rb:37-48`
during `Window#show_event`, that none of the 121 checks catch because none
of them assert "no critical/warning was logged" — and this persists
unchanged even though `ed5e9f43` added `lib/event_widget_pool.rb`
specifically to fix the double-build this assertion reports. This round's
rerun also surfaces, reading the full stderr instead of grepping for the
one known line: two `New application windows must be added after the
GApplication::startup signal has been emitted` criticals, repeated
`AdwToastOverlay ... exceeds AdwApplicationWindow width/size` warnings
through most of the run, and one `Finalizing GtkButton ..., but it still
has children left: - GtkPopover` warning near the end. See
`.reports/component-parity.md` for the mechanism and full detail on all of
these.

`rspec` was not run separately because there is nothing under `spec/` for
it to run; `rake spec` would report 0 examples, 0 failures — a suite that
has never been executed because it does not exist, which is its own kind of
gap, distinct from "exists but unrun."

## Verdict

- **Count**: 0 of 9 upstream test files ported. 0%.
- **Bijection**: none exists; the closest thing is 4 inline checks loosely
  covering 4 of the 9 files by subject, collapsed many-to-one and not named
  after upstream's test cases.
- **Runtime**: the one executable check this port has — the UI drive
  script — fails 3 of 121 checks on an actual run in this session, and
  surfaces a live GTK assertion failure the checks don't even look for.
  The runtime gate this audit was given (121/0) is contradicted by rerunning
  it, **for the second audit round in a row**, with the same 121/3-failed
  result both times despite the brief's claimed "components covered"
  number moving between rounds: do not trust a green claim without
  rerunning it yourself, and do not trust it more just because a later
  round repeats it.

This is not test parity. It is the near-total absence of ported tests, with
a UI driver that half-covers four model files by accident and currently
fails on its own terms besides.
