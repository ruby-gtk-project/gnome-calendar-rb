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

## Finding 2 — the runtime gate handed to this audit is false

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

## Verdict

Two real accountability failures: one phrase in the existing inventory that
frames an exclusion as settled rather than owned, and — far more serious —
a runtime gate this audit was handed that is false on rerun. The second one
alone means `clean: true` cannot be reported for this round regardless of
what the other four reports show, because the premise this audit was asked
to confirm against ("the runtime gate passed") is itself the false claim.
