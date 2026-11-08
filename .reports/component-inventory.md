# gnome-calendar upstream component inventory

Surveyed against `origin/main` (upstream GNOME Calendar, GTK4/libadwaita,
`src/` tree) versus this fork's `lib/` on `ruby`. This is the opening survey
of the fork: a map of what exists and what does not, one row per upstream
unit (a widget subclass, its `.blp` template where one exists, and the `.c`
file(s) that back it). It is not yet a widget/CSS/signal-level
`component-identification` pass on each file — that is the next step, done
per unit as each one is actually ported.

Totals: upstream has **73** `.c`/`.h` component-relevant source files (core +
gui + search + utils + weather), **44** `.blp` templates, 1 GSettings schema
(6 keys), 5 GResource manifests, and a `po/` catalogue of ~190 locales. This
fork's `lib/` has 37 files as of `f1159db7` (`lib/gnome_calendar/application.rb`
and `lib/gnome/calendar/rb/version.rb` are packaging scaffolding, not ported
components). Of the units below, **26 already exist** in `lib/`, **24 do not
exist at all** — updated from the prior 25/25 because `gcal-weather-service.c`
is now ported as `lib/weather_service.rb` (wired to the real `libgweather` gem
in `ebee87e6`); every other row's existence is unchanged from the prior pass.

## Window and application shell

| Upstream file(s) | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `src/gui/gcal-application.c/.h` | `lib/gnome_calendar/application.rb` | application class (actions, accelerators, CLI) | yes |
| `src/main.c` | `lib/main.rb` | entry point, About dialog, app actions | yes (gained `sync_color_scheme` via `ashpd`'s `Ashpd::Settings.color_scheme` at startup in `ebee87e6`) |
| `src/gui/gcal-window.c/.h` + `gcal-window.blp` | `lib/window.rb` | main `Adw.ApplicationWindow` | yes |
| `src/gui/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | keyboard shortcuts window | yes |
| `src/appdata/org.gnome.Calendar.metainfo.xml.in.in` | — | AppStream metadata (About dialog release notes, screenshots) | **no** |
| `data/org.gnome.Calendar.desktop.in.in` | — | desktop launcher entry, actions (new-event) | **no** |
| `data/org.gnome.calendar.gschema.xml.in` | `lib/settings.rb` | GSettings schema (6 keys) | yes (hand-mirrored, see note below) |
| `data/org.gnome.Calendar.search-provider.ini.in` + `data/shell-search-provider-dbus-interfaces.xml` | — | shell search provider D-Bus registration | **no** |
| `src/core/gcal-shell-search-provider.c/.h` | — | shell search provider implementation | **no** |

## Core data/model layer (`src/core/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-calendar.c/.h` | `lib/calendar.rb` | model: one calendar/source | yes |
| `gcal-calendar-monitor.c/.h` | — | monitors a calendar's events | **no** |
| `gcal-clock.c/.h` | `lib/clock.rb` | ticking clock service | yes |
| `gcal-context.c/.h` | `lib/context.rb` | app-wide context (manager, clock, settings) | yes |
| `gcal-event.c/.h` | `lib/event.rb` | model: one event | yes |
| `gcal-event-attendee.c/.h` | `lib/event_attendee.rb` | model: one attendee | yes |
| `gcal-event-list.c/.h` | `lib/event_list.rb` | sorted list of events | yes |
| `gcal-event-organizer.c/.h` | `lib/event_organizer.rb` | model: event organizer | yes |
| `gcal-global.c/.h` | `lib/global.rb` | process-wide globals/helpers | yes (ported in `ed5e9f43`, after this inventory was first written; `component-parity.md` was not re-walked for it) |
| `gcal-manager.c/.h` | `lib/manager.rb` | ESource/calendar manager, sync | yes (gained `discover_system_calendar_sources` via `edataserver`'s `EDataServer::SourceRegistry` and `add_calendar_from_url` via `soup3`'s `Soup::Session`, both in `ebee87e6`) |
| `gcal-range.c/.h` | `lib/range.rb` | date range value type | yes |
| `gcal-range-tree.c/.h` | `lib/range_tree.rb` | interval tree of ranges | yes |
| `gcal-recurrence.c/.h` | `lib/recurrence.rb` | recurrence rule model | yes |
| `gcal-time-zone-monitor.c/.h` | — | system timezone change monitor | **no** |
| `gcal-timeline.c/.h` + `gcal-timeline-subscriber.c/.h` | — | event timeline + subscriber interface (feeds agenda/week/month views) | **no** |
| `gcal-timer.c/.h` | `lib/timer.rb` | periodic timer service | yes |

## Utils (`src/utils/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-date-time-utils.c/.h` | `lib/date_time_utils.rb` | date/time formatting helpers | yes |
| `gcal-gui-utils.c/.h` | `lib/utils.rb` | GUI helper functions | yes (partial — see parity pass) |
| `gcal-utils.c/.h` | `lib/utils.rb` | misc helpers | yes (partial — see parity pass) |
| `gcal-source-discoverer.c/.h` | — | discovers available ESource backends for new-calendar flow | **no** |

## Search (`src/search/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-search-engine.c/.h` | — | drives the search popover/results | **no** |
| `gcal-search-model.c/.h` | — | `Gio::ListModel` of search hits | **no** |
| `gcal-search-hit.c/.h` | — | base search-hit model | **no** |
| `gcal-search-hit-event.c/.h` | — | search hit: one event | **no** |
| `src/gui/gcal-search-button.c/.h` + `.blp` | — | header-bar search entry/button, triggers search mode | **no** |

## Weather (`src/weather/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-weather-info.c/.h` | `lib/weather_service.rb` (inline, via `GWeather::Info`) | model: one weather forecast entry (GWeather-backed) | yes (folded into `WeatherService`, no separate model file — see note below) |
| `gcal-weather-service.c/.h` | `lib/weather_service.rb` | fetches/caches forecasts via `libgweather` | yes (ported in `ebee87e6`, wired to MonthCell's icon/temperature; see note below on the missing automatic-location path) |
| `src/gui/gcal-weather-settings.c/.h` + `.blp` | — | weather enable/location preferences row | **no** |

## Common widgets (`src/gui/common/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-date-chooser.c/.h` + `.blp` | `lib/date_chooser.rb` | month date-picker grid | yes |
| `gcal-date-chooser-day.c/.h` + `.blp` | `lib/date_chooser_day.rb` | one day cell in the date chooser | yes |
| `gcal-calendar-row.c/.h` + `.blp` | `lib/calendar_row.rb` | one calendar in a list (checkbox + color + name) | yes |
| `gcal-calendar-combo-row.c/.h` + `.blp` | — | `Adw.ComboRow` to pick a calendar | **no** |

## Calendar management dialog (`src/gui/calendar-management/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-calendar-management-dialog.c/.h` + `.blp` | — | top-level calendars-management `Adw.Dialog` | **no** |
| `gcal-calendar-management-page.c/.h` | — | shared page base for management dialog pages | **no** |
| `gcal-calendars-page.c/.h` + `.blp` | — | list of all calendars page | **no** |
| `gcal-edit-calendar-page.c/.h` + `.blp` | — | edit one calendar's properties page | **no** |
| `gcal-new-calendar-page.c/.h` + `.blp` | — | add new calendar/account page | **no** |
| `calendar-row.blp` (management variant) | — | row used inside `gcal-calendars-page` (distinct from `gui/common`'s row) | **no** |

## Event editor dialog (`src/gui/event-editor/`) — entirely missing

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-event-editor-dialog.c/.h` + `.blp` | — | top-level event-editing `Adw.Dialog` | **no** |
| `gcal-event-editor-section.c/.h` | — | base class for editor sections | **no** |
| `gcal-event-schedule.c/.h` | — | editor schedule sub-model | **no** |
| `gcal-summary-section.c/.h` + `.blp` | — | title/calendar/all-day summary section | **no** |
| `gcal-schedule-section.c/.h` + `.blp` | — | start/end date-time section | **no** |
| `gcal-reminders-section.c/.h` + `.blp` | — | reminders/alarms list section | **no** |
| `gcal-alarm-row.c/.h` + `.blp` | — | one alarm row in reminders section | **no** |
| `gcal-notes-section.c/.h` + `.blp` | — | description/notes text section | **no** |
| `gcal-attendees-section.c/.h` + `.blp` | — | attendees list section | **no** |
| `gcal-attendee-row.c/.h` + `.blp` | — | one attendee row | **no** |
| `gcal-attendee-summary-row.c/.h` + `.blp` | — | collapsed attendee summary row | **no** |
| `gcal-attendee-details-page.c/.h` + `.blp` | — | attendee detail sub-page | **no** |
| `gcal-organizer-row.c/.h` + `.blp` | — | organizer display row | **no** |
| `gcal-date-selector.c/.h` + `.blp` | — | date picker control used in editor | **no** |
| `gcal-date-time-chooser.c/.h` + `.blp` | — | date+time picker control | **no** |
| `gcal-date-chooser-row.c/.h` + `.blp` | — | `Adw.ActionRow` wrapping a date chooser popover | **no** |
| `gcal-time-zone-dialog.c/.h` + `.blp` | — | timezone picker dialog | **no** |
| `gcal-time-zone-dialog-row.c/.h` + `.blp` | — | one timezone row in that dialog | **no** |
| `gcal-multi-choice.c/.h` + `.blp` | `lib/multi_choice.rb` | multi-choice recurrence/alarm selector widget | yes |

## Importer (`src/gui/importer/`) — entirely missing

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-import-dialog.c/.h` + `.blp` | — | ICS import `Adw.Dialog` | **no** |
| `gcal-import-file-row.c/.h` + `.blp` | — | one event-to-import row | **no** |
| `gcal-importer.c/.h` | — | ICS parsing/import logic | **no** |

## Main window chrome (`src/gui/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-calendar-list.c/.h` + `.blp` | `lib/calendar_list.rb` | sidebar list of calendars | yes (gained a read-only row group for system/GOA sources discovered via `edataserver`, and a "subscribe from URL" row that imports via `soup3`, both in `ebee87e6`) |
| `gcal-calendar-navigation-button.c/.h` + `.blp` | `lib/calendar_navigation_button.rb` | prev/next/today navigation button | yes |
| `gcal-sync-indicator.c/.h` + `.blp` | `lib/sync_indicator.rb` | header-bar sync spinner | yes |
| `gcal-quick-add-popover.c/.h` + `.blp` | `lib/quick_add_popover.rb` | "new event" quick-add popover | yes |
| `gcal-event-popover.c/.h` + `.blp` | `lib/event_popover.rb` | event detail popover | yes |
| `gcal-event-widget.c/.h` + `.blp` | `lib/event_widget.rb` | event chip/pill drawn on views | yes |
| `gcal-event-widget-pool.c/.h` | `lib/event_widget_pool.rb` | recycling pool for event widgets | yes (ported in `ed5e9f43`, after this inventory was first written; see `.reports/component-parity.md` — the known `event_widget.rb` double-`build` GTK-CRITICAL this was expected to fix is confirmed, by rerunning the drive script, to still fire) |
| `gcal-meeting-row.c/.h` + `.blp` | `lib/meeting_row.rb` | "join meeting" row in event popover | yes |
| `gcal-drop-overlay.c/.h` | — | drag-and-drop ICS file overlay | **no** |
| `gcal-fading-label.c/.h` | — | label that fades instead of ellipsizing | **no** |
| `gcal-overflow-bin.c/.h` + `gcal-overflow-bin-layout.c/.h` | — | custom layout manager for overflowing children (month cells) | **no** |
| `gcal-bidi.c/.h` | — | bidi text helper | **no** |
| `gcal-tests.c/.h` | — | test-only widget registration hooks | **no** (test infra, not user-facing) |

## Views (`src/gui/views/`)

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `gcal-view.c/.h` | `lib/view.rb` | shared view interface/base | yes |
| `gcal-view-private.h` | — | private shared view helpers | n/a (header only) |
| `gcal-month-view.c/.h` + `.blp` | `lib/month_view.rb` | month grid view | yes |
| `gcal-month-view-row.c/.h` | — | one week row inside month view | **no** |
| `gcal-month-cell.c/.h` + `.blp` | `lib/month_cell.rb` | one day cell in month view | yes |
| `gcal-month-popover.c/.h` + `.blp` | `lib/month_popover.rb` | "+N more events" popover from month cell | yes |
| `gcal-agenda-view.c/.h` + `.blp` | `lib/agenda_view.rb` | agenda/list view | yes |
| `gcal-agenda-view-day.c/.h` | `lib/agenda_view_day.rb` | one day group in agenda view | yes |
| `gcal-agenda-view-day-row.c/.h` + `.blp` | `lib/agenda_view_day_row.rb` | one event row in agenda view | yes |
| `gcal-week-view.c/.h` + `.blp` | — | week grid view (entire week view) | **no** |
| `gcal-week-grid.c/.h` | — | hour-by-day grid inside week view | **no** |
| `gcal-week-header.c/.h` + `.blp` | — | week view's day-of-week header row | **no** |
| `gcal-week-hour-bar.c/.h` | — | week view's hour-of-day side bar | **no** |
| `gcal-week-view-common.c/.h` | — | shared week-view helpers (today line, DnD) | **no** |

## Styling / resources

| Upstream file | `lib/*.rb` target | Kind | Exists? |
|---|---|---|---|
| `src/theme/style.css`, `src/theme/events.css` | `lib/style.rb` | CSS classes (event colors, calendar accents) | yes (needs a parity check against the two CSS files) |
| `src/gui/*.gresource.xml`, `src/gui/*/*.gresource.xml`, `src/theme/theme.gresource.xml`, `src/appdata/appdata.gresource.xml.in`, `src/gui/icons/icons.gresource.xml` | n/a — Ruby port has no `.ui`/GResource bundle by house style | n/a | n/a |
| `src/gui/icons/*.svg` (11 symbolic icons) | — | custom symbolic icons the widgets reference (`calendar-agenda-symbolic`, `calendar-month-symbolic`, `calendar-week-symbolic`, `calendar-today-symbolic`, `clock-alt-symbolic`, `globe-symbolic`, `map-symbolic`, `share-symbolic`, `edit-symbolic`, `eye-not-looking-symbolic`, `add-reminder-symbolic`, `external-link-symbolic`, `check-plain-symbolic`, `checkmark-small-symbolic`, `info-outline-symbolic`, `loupe-large-symbolic`) | **no** (not yet verified present as app resources) |

## Localization

| Upstream | Target | Kind | Exists? |
|---|---|---|---|
| `po/*.po` (~190 locale files) + `po/POTFILES.in`/`LINGUAS` | — | message catalogue | **not yet surveyed** — translation-parity pass still needed |

## Summary of what `lib/` already has but does not map 1:1 above

- `lib/multi_choice.rb` ported, but it is the only piece of the whole
  `src/gui/event-editor/` tree that exists — the event editor dialog itself,
  every section, every row and the timezone dialog are all missing. There is
  currently **no way to create or edit an event's full detail** in the port
  beyond the quick-add popover.
- Three of five app surfaces that a user reaches from the header bar are
  unported: calendar management (`+`-menu → manage calendars), the importer
  (open `.ics` file), and search.
- The week view — one of the three primary calendar views (month/week/agenda)
  — does not exist at all; only month and agenda are ported.
- `gcal-weather-service.c`/`gcal-weather-info.c` are now ported as
  `lib/weather_service.rb`, wired to the mandatory `libgweather`/`GWeather`
  gem and feeding MonthCell's weather icon/temperature (`ebee87e6`). The
  weather *settings row* (`gcal-weather-settings.c/.h` + `.blp`) is still
  unported — there is no UI to change the weather location or toggle it on,
  only the schema keys `lib/settings.rb` already mirrors.
- `gcal-shell-search-provider.c` (GNOME Shell search integration) is
  unported, and its D-Bus/`.ini` registration files are not referenced
  anywhere in `lib/`.

## Notes for the next pass

- This inventory is file/unit-level ("does a port file exist"), per the
  survey exception in the `component-identification` skill. A real
  widget/CSS/signal/action table (the skill's normal per-file output) still
  needs to be built for each unit as it is actually ported — start with
  `gcal-window.blp` and the already-ported views, since those are the ones
  most likely to have silently drifted.
- `lib/settings.rb`'s own header comment documents that it hand-mirrors the
  GSettings schema instead of using real GSettings, to avoid requiring a
  compiled-schema install step. That is a local design note already recorded
  in the file; it is flagged here only so it is visible from the inventory,
  not re-litigated.
- Gem wiring (`ashpd`, `edataserver`, `libgweather`, `soup3`) is now done and
  proven on the drive script's live path (`ebee87e6`, `f1159db7`): each gem
  is required and called from `lib/weather_service.rb`, `lib/manager.rb`,
  `lib/calendar_list.rb` and `lib/main.rb`, and nothing in the gemspec is
  declared-but-unused. None of the four is unwound by this pass.
- Still open from the prior pass: a real widget/CSS/signal/action table per
  unit (the skill's normal per-file output) has not been built yet for any
  already-ported file — start with `gcal-window.blp` and the already-ported
  views, since those are the ones most likely to have silently drifted.
