# gnome-calendar-rb — translation parity

Per the `translation-parity` skill: parity requires the same (msgctxt,
msgid) key set, byte-identical, plus the same languages shipped and built.

## Upstream

`git show origin/main:po/POTFILES.in` lists 72 source files that contribute
translatable strings (46 `.blp` + 26 `.c`/`.h`, including the `data/`
metainfo and desktop files per upstream's POTFILES.in convention).
`git show origin/main:po/LINGUAS` lists **78 shipped locales**. A rough
occurrence count of `_(` / `C_(` calls across those 72 files comes to
**~355** marked-string call sites (this is call sites, not deduplicated
msgids — the real msgid count after `xgettext` dedup and template merge
will be lower, but every one of those call sites is a translatable string
upstream ships and a translator somewhere has translated into some subset
of 78 languages).

## Port

```
find . -iname "po" -o -iname "*.pot" -o -iname "*.mo"   → nothing, anywhere
grep -rn "gettext" lib                                   → nothing
grep -rn "_(" lib                                         → nothing (no
  marked strings; no gettext require anywhere in lib/)
```

There is:
- no `po/` directory,
- no `.pot` template,
- no `gettext` dependency required anywhere in `lib/`,
- no `_()`/`C_()`/`N_()` marking convention adopted anywhere in the port,
- no `LINGUAS` file,
- no `.mo` compiled anywhere in the tree.

## Verdict

**0 of upstream's ~355 marked call sites (and however many deduplicated
msgids that resolves to) have any Ruby counterpart marked for translation.
0 of 78 shipped languages are carried forward. This is not partial
translation parity — it is the total absence of an internationalization
layer in the port.**

Every user-visible string currently in `lib/*.rb` — window titles, button
labels, the "New Event Today" quick-add heading the drive script checks at
step 3, the toast text, the About dialog metadata — is a hardcoded English
Ruby string literal with no lookup key, so even if a `po/` directory
appeared tomorrow, none of the existing strings would already be marked
correctly; the marking work and the catalogue work both start from zero.

This also means the byte-identical-msgid requirement is moot in the "already
matches but needs verifying" sense: there is nothing to compare bytes
against, because there is no port-side msgid to begin with. The gap is not
"some labels were reworded"; it is "the mechanism that would let any label
be translated does not exist."

## What this blocks

All 78 of upstream's shipped languages — including large ones upstream
carries real contributor history for — lose every string in this port, not
degrade: a `ja` or `de` user running `gnome-calendar-rb` sees 100% English,
not "the new parts are English." Nothing in `AGENTS.md`, `Rakefile`, or the
gemspec sets up a `gettext`/`fast_gettext`-equivalent build step, a `.pot`
extraction task, or a `.mo` compile step, so there is also no scaffolding to
hang the eventual translation work on — it would need to be built, not
just filled in.

## Gap

Translation parity: 0%. No msgid census exists to diff against upstream's
because the port extracts none. No languages ship. No marking convention is
in use. This is a complete gap, not a partial one, and nothing in the
repository currently in progress addresses it — there is no commit, no
TODO, no section of `.reports/component-inventory.md`'s remaining-port-order
list that names `po/` or a gettext setup task at all (that list's final
item mentions "the translation catalogue" once, with no concrete plan).
