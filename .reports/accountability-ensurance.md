# gnome-calendar-rb — accountability ensurance

Per the `accountability-ensurance` skill: hunt phrases that present missing
work as a settled decision, and the runtime gate's own claim of health.

## Finding 1 — "deliberately out of scope" in `.reports/component-inventory.md`

Line 44 of `.reports/component-inventory.md`:

> Four upstream `.c` files contribute no component and are deliberately out
> of scope: `src/contrib/gdkarrayimpl.c` (a GdkArray macro instantiation),
> `src/core/gcal-global.c` and `src/core/gcal-log.c` (process init and
> logging), and `src/gui/gcal-tests.c` (an in-tree test harness hook).

This is exactly the forbidden phrasing pattern the skill exists to catch:
"deliberately out of scope" frames an exclusion as a settled design
decision. The skill's rule is explicit — the only sentence a document may
contain about a missing feature is one that admits the writer did not build
it, in the same breath. "Deliberately out of scope," even when the
underlying technical judgment is probably correct (a macro-instantiation
file, a logging/init file, and an in-tree test-harness hook genuinely do
not map to a UI component or a core model the way everything else in
`src/` does), is written in the voice of authority rather than confession,
and the next agent reading it will treat the question as closed rather than
reopening it. **I am not undoing the exclusion** — these four files
plausibly really do contribute nothing portable — but the sentence needs to
own that this is this agent's judgment call, stated as such, not a
pre-approved scope boundary. Flagging it here so the next reader does not
inherit it as settled.

## Finding 2 — the runtime gate handed to this audit is false, again, for a second round

**Update for this round:** the task brief handed to this round of the audit
repeats the identical claim with one number changed: "The runtime gate this
round: drive_ok=true, 121 checks passed, 0 failed, covering 39 components"
(previously 26 components). Current HEAD is `ed5e9f43`, two commits past
where this finding was first written. This audit reran the drive script
again, from scratch, against that HEAD, before writing anything, and the
result is byte-for-byte the same failure as last round — same 118/121, same
three named failures. **A false green was handed to this audit a second
time, after the first audit already reported it false in writing and
pushed that report to the same branch this brief was generated from.**
Whatever produces "0 failed" either does not read `.reports/test-parity.md`
or does not rerun the script at all; either way, the fix is not "trust it
less" but "never trust it, every round, and rerun it yourself" — which is
what this audit did, again:

Original finding text, still true, now confirmed twice over two separate
audit rounds two commits apart:

The task brief for this audit stated: "The runtime gate this round:
drive_ok=true, 121 checks passed, 0 failed, covering 26 components." This
audit reran the exact command
(`nix develop --command xvfb-run -a ruby test/drive_gnome_calendar.rb`)
in this session, on this checkout of `ruby`, with no changes made, and got:

```
118 of 121 checks passed
  failed check: the narrow switcher is in the bin
  failed check: the main window never collapsed
  failed check: its navigation is still showing
DRIVE FAILED (3)
```

**This is the single most serious finding in this audit: a green runtime
claim (0 failed) was handed to an auditor and does not reproduce.** Whoever
or whatever produced "121 passed, 0 failed" either ran it before the
regression landed, ran a different invocation, or reported a result that
was never actually observed. Per the skill, a false green in a report is
the most serious category of finding there is, worse than an honestly
reported gap, because it actively misleads whoever reads it next into
believing a thing is proven that is not. This audit does not know which of
those explanations is true — only that the number this audit was told to
treat as a gate does not hold under a rerun, and that rerunning it, rather
than trusting it, is what caught this.

## Finding 3 — the drive script treats a runtime GTK assertion as invisible

`test/drive_gnome_calendar.rb`'s 121 checks produced "118 passed" while a
`Gtk-CRITICAL` assertion failure (`gtk_box_append: assertion
'gtk_widget_get_parent (child) == NULL' failed`) fired four times during
step 8 of the same run, from `lib/event_widget.rb` via
`Window#show_event`. None of the 121 checks look at stderr or at whether a
critical/warning was logged, so a real defect in a component the inventory
marks "present" produces a loud, repeated engine-level assertion and the
suite still calls it 118/121 "passed" for reasons unrelated to that defect.
This is not a lie anyone wrote down — no comment claims the suite checks
for criticals — but it is a gap between what "DRIVE FAILED (3)" sounds like
it covers (the whole app) and what it actually covers (121 specific
property checks, none of which is "nothing exploded"). See
`.reports/component-parity.md` for the mechanism and
`.reports/test-parity.md` for the full rerun transcript.

## What was checked and came back clean

- `grep -rniE "TODO|FIXME|not implemented|for now|in a future"` across
  `lib/`, `exe/`, `.reports/`, and a search for `PORTING.md` (it does not
  exist in this repo — the task brief assumed a file this port never
  created; its absence is itself worth noting, since the house convention
  seen in the pilot port keeps one) returned **no hits**. The port does not
  contain any TODO/FIXME-style deferred-work markers, and no excusing
  language beyond the one sentence in Finding 1.
- `.reports/component-inventory.md` elsewhere states its gaps in the blunt,
  non-excusing register the skill asks for — e.g. "44 user-facing
  components remain," "0 of 7," with no softening language — Finding 1 is
  the one exception in an otherwise plainly-written document.

## Finding 4 (new this round) — a "fix" commit landed and the defect it targeted was never reverified

`ed5e9f43`'s commit message says `EventWidgetPool` was wired into
`MonthCell`, `MonthPopover` and `AgendaViewDayRow` — the three call sites
`component-parity.md` named as the double-`build` bug's origin — but
nothing in that commit, in `.reports/`, or anywhere else in the repository
records whether the drive script was rerun afterward to confirm the fix
actually closed the gap it was aimed at. This audit reran it: the identical
`Gtk-CRITICAL` fires the identical four times (see
`.reports/component-parity.md`). No document claimed this was fixed — so
this is not a false-green claim the way Finding 2 is — but shipping a
targeted fix commit with no verification that it worked, on a known and
previously-reported defect, is the same failure one step earlier: writing
code that addresses a report's wording ("reuses EventWidget instances
across rebuilds") without checking it addresses the report's actual
finding (a specific assertion at a specific line, reproducible by running
one script).

## Finding 2 (continued) — third consecutive round, and the false claim is now also in the commit log itself

**Update for this round, HEAD `ba3a6af5`** (one commit past `ed5e9f43`, adding
`lib/calendar_navigation_button.rb` and the desktop/appdata/search-provider
data files). This round's task brief again repeats the pattern with a third
set of cosmetic numbers: "drive_ok=true, 129 checks passed, 0 failed,
covering 22 components." This audit reran the drive script twice from
scratch, before writing anything, per the task's mandatory runtime
instructions:

```
nix develop --command xvfb-run -a ruby test/drive_gnome_calendar.rb
...
126 of 129 checks passed
  failed check: the narrow switcher is in the bin
  failed check: the main window never collapsed
  failed check: its navigation is still showing
DRIVE FAILED (3)
```

Identical two runs, identical three named failures — the same breakpoint-
collapse bug in `lib/window.rb` reported in the first two audit rounds,
still unfixed. This is now **three consecutive rounds** in which the task
brief's "0 failed" gate has been handed to an auditor and has not
reproduced once. The check count climbed each round (121 → 121 → 129) in
lockstep with the brief's own "components covered" figure (26 → 39 → 22,
non-monotonic besides), which only makes it clearer that whatever produces
this gate number is reporting a plausible-looking pair of numbers, not an
actual rerun's output.

**This round the false claim is no longer confined to the task brief: it
is now written into the port's own commit history.** The commit that added
`calendar_navigation_button.rb` (`ba3a6af5`, "Port
gcal-calendar-navigation-button and the desktop/appdata/search-provider
data files") ends its message with: "Full drive run: 129 of 129 checks
passed." That sentence is false, reproducibly, on this exact checkout, by
rerunning the exact script the sentence refers to. Per the skill, a false
green claim is the single most serious category of finding — this one has
moved from an external gate value (which could be blamed on tooling
upstream of this repository) into a commit message the port's own author
wrote and pushed to `ruby`, which is strictly worse: it is now part of the
record this port keeps about itself, and the next reader of `git log` has
no reason to doubt it without rerunning the script themselves.

## Finding 5 (new this round) — `component-inventory.md` is stale against the file it is supposed to track

`.reports/component-inventory.md` line 140 still reads:

```
| `gcal-calendar-navigation-button.c/.h` + `.blp` | — | prev/next/today navigation button | **no** |
```

`lib/calendar_navigation_button.rb` has existed since `ba3a6af5`, the
current HEAD. The inventory was last updated at `47c10e95`, one commit
before the file it is now wrong about was added, and nothing updated it in
the intervening commit. This is a smaller instance of the same class of
problem as Finding 2: a document asserting a status that a one-command
check (`ls lib/calendar_navigation_button.rb`) disproves. It is a staleness
gap, not an invented excuse, but it means `component-identification.md`'s
and `component-parity.md`'s counts (carried over from this inventory in
past rounds) need to be taken from `ls lib/` directly each round rather
than from the inventory document, which this audit has done for this
round's reports.

## Verdict

Five real accountability failures, the central one now confirmed across
three separate audit rounds and escalated this round from an external gate
value into the port's own commit message: one phrase in the existing
inventory that frames an exclusion as settled rather than owned; a runtime
gate this audit was handed that is false on rerun, for a third round
running, after both prior rounds' findings of exactly this were already
written down and pushed to this branch; a fix commit whose target defect
was never reverified and is confirmed, across two rounds now, to still
reproduce unchanged; and (new this round) the inventory document itself
going stale against a file that was added after its last update, plus the
same "N of N passed" false claim now appearing verbatim inside a pushed
commit message rather than only in an external task brief. The runtime-gate
finding alone means `clean: true` cannot be reported for this round
regardless of what the other four reports show, because the premise this
audit was asked to confirm against ("the runtime gate passed") is itself
the false claim — and it is now false for the third consecutive round,
worse each time: round one, an external gate was wrong; round two, the
same wrong gate was repeated after being refuted in writing; round three,
the wrong claim propagated into the project's own git history.

## Round 2 correction — the runtime-gate finding's root cause, and what was actually fixed

The three breakpoint checks this and the two prior audit rounds reported
failing ("the narrow switcher is in the bin", "the main window never
collapsed", "its navigation is still showing") were re-investigated this
round rather than taken on faith from either side.

Reproduced: `nix develop --command xvfb-run -a ruby test/drive_gnome_calendar.rb`
(the invocation this round's task brief specified, and the one the two
prior audit rounds used) does give 126 of 129, failing exactly those three
checks, on HEAD before any change this round.

Also reproduced, same HEAD, no code changes: `nix develop --command xvfb-run
-a --server-args="-screen 0 1920x1080x24" ruby test/drive_gnome_calendar.rb`
— the exact invocation test/drive_gnome_calendar.rb's own header comment
has specified since before this round — gives 129 of 129, including all
three breakpoint checks, with no retry and no flakiness across two runs.

So the three breakpoint checks are not a bug in `lib/window.rb`'s
breakpoints: `xvfb-run -a` with no `--server-args` sizes the virtual
display far smaller than any of this window's three test sizes (900sp,
600sp, and the "wide" 1400sp main window), which clips every one of them
down near or under 1000sp regardless of what was requested — so the "wide"
control window also crosses the 1000sp breakpoint for real, which is
exactly why "the main window never collapsed" and "its navigation is still
showing" failed too: those assert on the *unclipped* window, which this
invocation never produces. `ba3a6af5`'s "Full drive run: 129 of 129 checks
passed" was not a fabrication reached by the author skipping the run — a
129/129 run is real and reproducible on that commit, just not through the
invocation this task brief's gate used. The commit message should still
have named the exact command it ran, and did not; that omission, not a
false count, is the defect in `ba3a6af5` worth owning, and is recorded here
rather than fixed by amending that commit (this branch does not rewrite
pushed history).

This round also found and fixed a real, independent defect flagged by the
same finding: `EventWidget#build` rebuilt its whole widget tree —
`container.append` on children already parented to it — on every call,
not just the first. `EventWidgetPool` calling `.tap(&:build)` on reuse, and
`Window#show_event` calling `widget.widget` on an `EventWidget` already on
screen (`lib/window.rb`'s `on_event_activated` handler), each re-ran it,
which is where the 4-per-run `Gtk-CRITICAL **: gtk_box_append: assertion
'gtk_widget_get_parent (child) == NULL' failed` came from — reproduced
before this fix, confirmed gone after it, both via the same
`--server-args="-screen 0 1920x1080x24"` invocation above. `EventWidget#build`
now memoizes the assembly the same way `Window#build` already did
(`unless @assembled`), and calls `refresh` + returns the button on every
call, so a second `build` or `.widget` on an already-built instance updates
its labels instead of re-parenting its children.
