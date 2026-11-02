# gnome-calendar-rb — upstream component inventory

Upstream: GNOME Calendar (C + blueprint), read from `origin/main` in this repo.
Port: the `ruby` branch, house style per `.claude/skills/ruby-gtk` (one upstream
source file → one `lib/<thing>.rb`, memoized widget methods, `.tap` config,
assembly in `build`).

## State of `lib/` on `ruby`

The port has a working shell and its default view. `lib/` on `ruby` now holds
36 files:

```
lib/main.rb                 lib/window.rb               lib/shortcuts_dialog.rb
lib/view.rb                 lib/month_view.rb           lib/month_cell.rb
lib/month_popover.rb        lib/agenda_view.rb          lib/agenda_view_day.rb
lib/agenda_view_day_row.rb  lib/event_widget.rb         lib/quick_add_popover.rb
lib/date_chooser.rb         lib/date_chooser_day.rb     lib/calendar_row.rb
lib/calendar_list.rb        lib/sync_indicator.rb       lib/multi_choice.rb
lib/context.rb              lib/manager.rb              lib/calendar.rb
lib/event.rb                lib/event_list.rb           lib/event_attendee.rb
lib/event_organizer.rb      lib/recurrence.rb           lib/range.rb
lib/range_tree.rb           lib/clock.rb                lib/timer.rb
lib/date_time_utils.rb      lib/utils.rb                lib/settings.rb
lib/style.rb
lib/gnome_calendar.rb       lib/gnome_calendar/application.rb   # packaging stubs
lib/gnome/calendar/rb/version.rb                                # kettle-jem
```

18 of the 61 user-facing components exist; 16 of the supporting model, service
and helper files exist. The week view, the whole event editor, calendar
management, the importer, search, weather and the event popover are all still
absent. Per-component status is in the table at the end.

The pilot port keeps the real app in flat `lib/*.rb` (`lib/main.rb` holds the
`App` class) and leaves `lib/<gem_name>/application.rb` as the untouched
packaging stub, so every target below is a flat `lib/*.rb`.

Upstream counts: 93 `.c` and 96 `.h` files under `src/`, 46 blueprint files,
1 GSettings schema (5 keys), 9 GResource manifests, 78 locales in
`po/LINGUAS`, 70 entries in `po/POTFILES.in`.

Four upstream `.c` files contribute no component and are deliberately out of
scope: `src/contrib/gdkarrayimpl.c` (a GdkArray macro instantiation),
`src/core/gcal-global.c` and `src/core/gcal-log.c` (process init and logging),
and `src/gui/gcal-tests.c` (an in-tree test harness hook).

---

## 1. Application and window

### `src/gui/gcal-application.c` → `lib/main.rb`

`Adw.Application` subclass. Not a widget, but it owns the app actions, the
accelerators, the About dialog, the D-Bus activation and the file-open handler.

| Facet | Detail |
|---|---|
| App actions | `app.open-event` (param `s`), `app.sync`, `app.search`, `app.about`, `app.quit` |
| Implicit actions | `app.shortcuts` (libadwaita-provided, loads `shortcuts-dialog.ui` from the gresource) |
| About | `Adw.AboutDialog` built from the appdata gresource — designers, developers, copyright, debug info (`Calendar.txt`), translator credits, a legal section |
| Other | handles `open` for `.ics` files → `GcalWindow.import_files`; CLI `--date`, `--uuid`, `--quit` |

### `src/gui/gcal-window.blp` + `src/gui/gcal-window.c` → `lib/window.rb`

The main window. The single largest component.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template) | 1 | — | `notify::current-breakpoint` → `on_breakpoint_changed` | title "Calendar", 800×600, min 360×600 |
| `Gtk.ShortcutController` | 1 | — | 19 `Shortcut` children | see accelerator table below |
| `Gtk.GestureClick` | 2 | — | `pressed` → back / forward | hardware buttons 8 and 9 |
| `Adw.ToastOverlay` `overlay` | 1 | — | — | hosts the delete-undo and import-error toasts |
| `$GcalDropOverlay` `drop_overlay` | 1 | — | — | own component, below |
| `Adw.StatusPage` `drop_status_page` | 1 | `drop-overlay-area`, `compact` | — | "Drop Event Files to Import" **(empty/drop state)** |
| `Adw.OverlaySplitView` `split_view` | 1 | `drop-target` | — | pinned sidebar, collapses at breakpoints |
| `Gtk.DropTarget` `drop_target` | 1 | — | `accept`, `drop` | capture phase, copy action |
| `Adw.ToolbarView` | 2 | `view` (content one) | — | sidebar + content |
| `Adw.HeaderBar` | 2 | — | — | sidebar bar and `header_bar` |
| `Gtk.ToggleButton` `sidebar_button` | 1 | — | bound to `split_view.show-sidebar`; own `ShortcutController` F9 | "Toggle Sidebar" |
| `$GcalSyncIndicator` | 1 | — | — | own component |
| `$GcalCalendarNavigationButton` | 1 | — | — | header title widget |
| `Gtk.MenuButton` `menu_button` | 1 | — | popover `win_menu` | "Main Menu", primary |
| `$GcalSearchButton` | 1 | — | — | own component |
| `Adw.ViewStack` `views_stack` | 1 | `view` | `notify::visible-child` → `view_changed` | 3 pages |
| `Adw.ViewStackPage` | 3 | — | — | `_Month`/`_Week`/`_Agenda`, icons `calendar-{month,week,agenda}-symbolic`; agenda hidden until narrow |
| `Gtk.ActionBar` | 1 | — | — | bottom bar |
| `Gtk.Button` `previous_date_button` / `next_date_button` | 2 | — | `win.previous-date`, `win.next-date` | icon + tooltip bound per view: Previous/Next Week, Month, Yesterday/Tomorrow |
| `Gtk.Button` + `Adw.ButtonContent` | 1 | — | `win.today` | "_Today", `calendar-today-symbolic` |
| `Adw.Bin` `view_switcher_bin` | 1 | — | — | swaps wide ↔ narrow switcher |
| `Adw.ViewSwitcher` `view_switcher_wide` | 1 | — | — | policy wide |
| `Adw.InlineViewSwitcher` `view_switcher_narrow` | 1 | `flat` | — | icons only, standalone root object |
| `Gtk.Button` (add event) | 1 | — | `win.new-event` | `list-add-symbolic` |
| `Gtk.Button` (manage calendars) | 1 | — | `win.show-calendars` | `x-office-calendar-symbolic` |
| `Adw.Breakpoint` | 2 | — | — | `max-width: 1000sp` → collapse + narrow switcher; `max-width: 700sp` → agenda-only, hide nav buttons and sidebar button |
| `Gtk.PopoverMenu` `win_menu` + `menu` | 1 | — | — | see menu table |
| `$GcalWeatherSettings` `weather_settings` | 1 | — | — | `custom: "weather"` slot in the menu |
| `$GcalQuickAddPopover` | 1 | — | `edit-event`, `closed` | own component |
| `$GcalEventEditorDialog` | 1 | — | `remove-event` | own component |
| `$GcalCalendarManagementDialog` | 1 | — | — | own component |
| sidebar `Gtk.Box` + `$GcalDateChooser` + `$GcalCalendarList` | 1 each | — | `day-selected` | `split-month-year: true` |

**Window actions** (`win.`): `change-view` (param `i`), `next-date`,
`previous-date`, `today`, `new-event`, `show-calendars`, `undo-delete-event`,
`open-date-time-settings`, `open-online-accounts`.

**Main menu model** — section 1: `_Synchronize Calendars` (`app.sync`);
section 2: `_Date & Time Settings…` (`win.open-date-time-settings`),
`_Online Accounts…` (`win.open-online-accounts`), submenu `Weather` with the
`weather` custom slot; section 3: `_Keyboard Shortcuts` (`app.shortcuts`),
`_About Calendar` (`app.about`).

**Accelerators bound on the window**: `<Control>t` / `<Alt>Down` / `Home` →
today; `<Alt>Left` / `Page_Up` → previous; `<Alt>Right` / `Page_Down` → next;
`<Control>Page_Down` → change-view(-1); `<Control>Page_Up` → change-view(-2);
`<Alt>1/2/3` → change-view(0/1/3); `<Ctrl>n` → new-event; `<Control>w` →
window.close; `<Control>q` → app.quit; `<Ctrl><Alt>m` and `F8` →
show-calendars; `<Ctrl>r` and `F5` → app.sync; `F9` → toggle sidebar
(on `sidebar_button`); `<Control>f` → search (on `GcalSearchButton`).

**Toasts** (error/undo states, built in `gcal-window.c`): "Event deleted" /
"Another event deleted" with an `_Undo` button → `win.undo-delete-event`;
"Could not import some files: Not ICS files"; "Could not import “%s”: Not an
ICS file".

### `src/gui/shortcuts-dialog.blp` → `lib/shortcuts_dialog.rb`

Standalone `Adw.ShortcutsDialog`, no backing source file. 3 sections, 16 items:

- **General** — Open Main Menu `F10`, Toggle Sidebar `F9`, New Event `<Primary>N`, Manage Calendars `F8 <Ctrl><Alt>m`, Synchronize Calendars `F5 <Ctrl>r`, Close Window `<Primary>Q <Primary>W`, Search `<Primary>F`, Show Help `F1`, Shortcuts `<Primary>question`
- **Navigation** — Go Back `<Alt>Left Page_Up`, Go Forward `<Alt>Right Page_Down`, Show Today `<Alt>Down <Primary>T Home`, Next View `<Primary>Page_Down`, Previous View `<Primary>Page_Up`
- **View** — Month View `<Alt>1`, Week View `<Alt>2`

---

## 2. Shared widgets (`src/gui/common/`)

### `gcal-date-chooser.blp` + `.c` → `lib/date_chooser.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template) | 1 | — | emits `day-selected` | props `active-date`, `show-heading`, `split-month-year`, `show-events`, `show-week-numbers`, `show-selected-week` |
| `Gtk.Grid` | 2 | — | — | header grid + day `grid` |
| `$GcalMultiChoice` | 3 (+2 in popover) | — | `notify::value` | month, year, combined (384 … 3839998); popover holds month + year copies |
| `Gtk.Popover` `popover` | 1 | `activatable`, `month` | — | combined-choice popover |
| `$GcalDateChooserDay` | **repeater** | — | — | 6×7 day cells built in `.c`, plus week-number labels and weekday headers |

### `gcal-date-chooser-day.blp` + `.c` → `lib/date_chooser_day.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Button` (template) | 1 | `circular`, `day`, `flat`, `text-button`; dynamic: `today`, `other-month`, `selected-week` | — | one day cell |
| `Gtk.Label` `label` | 1 | `day`, `numeric` | — | day number |
| `Gtk.Revealer` `dot_revealer` + `Adw.Bin` `dot` | 1 | css-name `dot` | — | "has events" dot |

### `gcal-calendar-row.blp` + `.c` → `lib/calendar_row.rb`

`Adw.PreferencesRow` with `Gtk.Image` `color_image` (`calendar-color-image`),
`Gtk.Label` `title_label` (ellipsize end), `Gtk.Image` `visibility_image`
(`eye-not-looking-symbolic`) and an initially-hidden `suffix` box.

### `gcal-calendar-combo-row.blp` + `.c` → `lib/calendar_combo_row.rb`

`Adw.ComboRow` titled "Calendar" with a `Gtk.SignalListItemFactory`
(`setup`/`bind`/`unbind`) rendering each calendar's colour swatch and name.

---

## 3. Views (`src/gui/views/`)

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `gcal-view.c/.h` (+ `gcal-view-private.h`) | `lib/view.rb` | interface / mixin | `GcalView` interface: `active-date`, `get_date`, `set_date`, `create-event`, `event-activated` |
| `gcal-month-view.blp` + `.c` | `lib/month_view.rb` | view | custom `Gtk.Widget`, CSS `month-view`; `[header]` box with 7 weekday `Gtk.Label`s (`header`, `heading`, `month-header`, `view`); `EventControllerKey`, two `EventControllerScroll` (kinetic + discrete), `GestureClick`, `EventControllerMotion`; signals `create-event`, `create-event-detailed`, `event-activated` |
| `gcal-month-view-row.c/.h` | `lib/month_view_row.rb` | widget (code-built) | one week row, lays out the 7 cells and the event widgets |
| `gcal-month-cell.blp` + `.c` | `lib/month_cell.rb` | widget | `Adw.BreakpointBin` (50×50 min, breakpoint `max-width: 120sp`), `day_label` (`day-label`, `numeric`), `weather_icon` (`dimmed`), `temp_label` (`dimmed`, `temp-label`), `content_space`, `overflow_button` (`flat`, `overflow`, tooltip "All Events") + `Gtk.Inscription`; accessible-role `grid_cell`, `activate` signal + shortcuts |
| `gcal-month-popover.blp` + `.c` | `lib/month_popover.rb` | popover | custom `Gtk.Widget`; `main_box` (`card`, `view`), `day_label` (`large-title`), close `Gtk.Button` (`flat`, `circular`), `listbox` (`calendar-list`), `new_event_button` "New Event…" (`flat`); action `month-popover.popdown` on `Escape` |
| `gcal-week-view.blp` + `.c` (+ `gcal-week-view-common.c`) | `lib/week_view.rb` | view | `Gtk.Box` (`week-view`); expander `Gtk.ToggleButton` (`flat`, `circular`, `week-header-expander`); `GestureZoom`, `EventControllerScroll`, `EventControllerMotion`, `ShortcutController` (Page_Up/Down); `Gtk.SizeGroup` over `expand_button_box` + `hours_bar`; zoom level persisted to GSettings |
| `gcal-week-header.blp` + `.c` | `lib/week_header.rb` | widget | custom widget (`week-header`); `weekdays_box`, scrolled `Gtk.Grid` for all-day events; `GestureClick`, `EventControllerMotion`; `expanded`/`can-expand` props; "Other events"/overflow labels built in `.c` |
| `gcal-week-grid.c/.h` | `lib/week_grid.rb` | widget (code-built) | the timed-event grid: drawing, drag-to-create, drop target, event layout |
| `gcal-week-hour-bar.c/.h` | `lib/week_hour_bar.rb` | widget (code-built) | hour labels down the left edge, 12/24h aware |
| `gcal-agenda-view.blp` + `.c` | `lib/agenda_view.rb` | view | `Gtk.Box`; `$GcalDateChooser`; `Gtk.ListView` + `Gtk.NoSelection` + `Gtk.FilterListModel` + `Gtk.BoolFilter`; `BuilderListItemFactory` making `$GcalAgendaViewDayRow` |
| `gcal-agenda-view-day-row.blp` + `.c` | `lib/agenda_view_day_row.rb` | row | `Adw.Bin`; `title_label` (`caption-heading`); `listbox` with `row-activated`; `[placeholder]` `Gtk.Label` "No events" (`no-events`, `dimmed`) **(empty state)** |
| `gcal-agenda-view-day.c/.h` | `lib/agenda_view_day.rb` | model object | `GListModel` of one day's events, props `date`, `n-items` |

---

## 4. Event display widgets (`src/gui/`)

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `gcal-event-widget.blp` + `.c` | `lib/event_widget.rb` | widget | custom `Gtk.Widget`; `Gtk.DragSource` (`prepare`, `begin`, propagation bound to calendar read-only), `GestureClick` (`pressed`, `released`); `Adw.Bin` `edge` (`edge`), `$GcalOverflowBin` `overflow_bin` (`content`) holding a vertical box (`$GcalOverflowBin` + dimmed timestamp `Gtk.Label` + `Gtk.Inscription`) and a horizontal box (`$GcalFadingLabel` + dimmed timestamp); CSS `slanted`, `slanted-start`, `slanted-end` applied from code; `activate` signal + shortcuts |
| `gcal-event-popover.blp` + `.c` | `lib/event_popover.rb` | popover | `Gtk.Popover` (`event-popover`); `Adw.Clamp` 400; `summary_label` (`title-4`), `date_time_label` (`dimmed`), `read_only_icon` (`changes-prevent-symbolic`, `dimmed`, tooltip "This event is part of a read-only calendar"), `ics_export_button` (`circular`, `share-symbolic`, "Export Event"), `action_button` (`circular`); `placeholder_label` "No event notes" (`dimmed`, `no-events`) **(empty state)**; scrolled `description_label`; `location_box` with "Location" heading, `location_label` and a map `Gtk.Button` (`circular`, `map-symbolic`); `meetings_box` with `meetings_listbox` (`calendar-list`) |
| `gcal-meeting-row.blp` + `.c` | `lib/meeting_row.rb` | row | `Gtk.ListBoxRow`; `title` (`heading`), `subtitle` (ellipsize), `join_button` "_Join" (`suggested-action`) |
| `gcal-quick-add-popover.blp` + `.c` | `lib/quick_add_popover.rb` | popover | `Gtk.Popover` (`quick-add-popover`, 360 wide); `title_label` (`title-4`); `Adw.EntryRow` `summary_entry` "Title" (`notify::text`, `entry-activated`); scrolled `calendars_list_box` (`boxed-list`, `calendars-list`, `compact`, `row-selected`); `edit_button` "_Edit Details" and `add_button` "_Save Event" (`suggested-action`); signal `edit-event` |
| `gcal-search-button.blp` + `.c` | `lib/search_button.rb` | widget | `Adw.Bin`; `EventControllerFocus`; `Gtk.Stack` (`suggestionbutton`) with a `Gtk.Button` page (`edit-find-symbolic`, "Search Events", global `<Control>f`) and a `Gtk.SearchEntry` page ("Search events", 500 ms delay, `activate`/`next-match`/`previous-match`/`search-changed`/`stop-search`, Up/Down shortcuts); `Gtk.Popover` (`menu`) with `Gtk.Revealer`, `Gtk.ListView` `results_listview` + `Gtk.SingleSelection` + `BuilderListItemFactory` row (`Gtk.Image` `title`, title `Gtk.Label`, `separator` "—" (`dimmed`), `subtitle` (`subtitle`)) |
| `gcal-sync-indicator.blp` + `.c` | `lib/sync_indicator.rb` | widget | `Adw.Bin` + `Gtk.Stack` (crossfade) with `empty`, `spinner` (`Adw.Spinner`, "Synchronizing Remote Calendars") and `success` (`checkmark-small-symbolic`) pages |
| `gcal-calendar-navigation-button.blp` + `.c` | `lib/calendar_navigation_button.rb` | widget | `Adw.Bin` + `Gtk.Stack`: `active` page is a `Gtk.MenuButton` "_Choose Date" (always-show-arrow) with a `Gtk.Popover` holding a `$GcalDateChooser`; `inactive` page is a `Gtk.Label` (`heading`) |
| `gcal-calendar-list.blp` + `.c` | `lib/calendar_list.rb` | widget | `Adw.Bin` → `ScrolledWindow` → `Adw.Clamp` 800 → `calendar_listbox` (`navigation-sidebar`, `row-activated`) with a capture-phase `ShortcutController` re-binding Page_Up/Page_Down to `win.previous-date`/`win.next-date`; rows are `$GcalCalendarRow` (**repeater** over the calendar model) |
| `gcal-weather-settings.blp` + `.c` | `lib/weather_settings.rb` | menu popover content | `Gtk.Box`; "Show Weather" `Gtk.Switch`; "Automatic Location" `Gtk.Switch` in `weather_auto_location_box`; `weather_location_entry` ("Search locations", `edit-find-symbolic`) with a GWeather location completion |
| `gcal-drop-overlay.c/.h` | `lib/drop_overlay.rb` | widget (code-built) | reveals the "Drop Event Files to Import" overlay on drag-over; CSS `drop-overlay-area`, `blurred` |
| `gcal-fading-label.c/.h` | `lib/fading_label.rb` | widget (code-built) | label that fades instead of ellipsizing; prop `text`, `align` |
| `gcal-overflow-bin.c/.h` + `gcal-overflow-bin-layout.c/.h` | `lib/overflow_bin.rb` | widget + layout manager | picks between its children by available size; prop `request-mode` |
| `gcal-event-widget-pool.c/.h` | `lib/event_widget_pool.rb` | helper | recycles `GcalEventWidget`s for the views |
| `gcal-bidi.c/.h` | `lib/bidi.rb` | helper | RTL/LTR direction helpers used by the views |

---

## 5. Event editor (`src/gui/event-editor/`)

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `gcal-event-editor-dialog.blp` + `.c` | `lib/event_editor_dialog.rb` | dialog | `Adw.Dialog` 700×1000; `Adw.NavigationView` with `main_page` and `$GcalAttendeeDetailsPage`; `Adw.HeaderBar` with `cancel_button` "_Cancel" and `done_button` "_Done" (`suggested-action`, `event-editor.save`) in a vertical `Gtk.SizeGroup`; `Adw.PreferencesPage` with an `Adw.Banner` ("This event is in a read-only calendar…", revealed when not writable) **(error/read-only state)**; sections in order: summary, calendar combo row, schedule, attendees, reminders, notes; `delete_group` with an `Adw.ButtonRow` "_Delete Event" (`destructive-action`); `ShortcutController` `<Control>s` → `event-editor.save`; action `event-editor.save`; signal `remove-event` |
| `gcal-event-editor-section.c/.h` | `lib/event_editor_section.rb` | interface / mixin | `GcalEventEditorSection`: `set_event`, `apply`, `changed`, prop `dialog` |
| `gcal-summary-section.blp` + `.c` | `lib/summary_section.rb` | section | two `Adw.EntryRow`s: "Title" `summary_entry`, "Location" `location_entry`, both `editable` bound to writability |
| `gcal-schedule-section.blp` + `.c` (+ `gcal-event-schedule.c/.h` → `lib/event_schedule.rb`) | `lib/schedule_section.rb` | section | `Adw.InlineViewSwitcher` + `Adw.ViewStack` with `_All Day` (two `$GcalDateChooserRow`s, `separate-rows`) and `_Time Slot` (two `$GcalDateTimeChooser`s) pages; `repeat_combo` "Repeat" (`StringList`: No Repeat, Daily, Monday – Friday, Weekly, Monthly, Yearly); `repeat_duration_combo` "End Repeat" (Forever, Number of Occurrences, Until Date); `Adw.ActionRow` + `Gtk.SpinButton` "Number of Occurrences" (adjustment 2…999999999); `Adw.ActionRow` + `$GcalDateSelector` "End Repeat Date" |
| `gcal-date-chooser-row.blp` + `.c` | `lib/date_chooser_row.rb` | row | `Adw.EntryRow` + `EventControllerFocus` + `Gtk.MenuButton` (`flat`, `calendar-month-symbolic`, "Edit Date") whose `Gtk.Popover` holds a `$GcalDateChooser` with week numbers |
| `gcal-date-time-chooser.blp` + `.c` | `lib/date_time_chooser.rb` | group | `Adw.PreferencesGroup`: `$GcalDateChooserRow` "Date" + `Adw.EntryRow` "Time" with a `Gtk.MenuButton` (`flat`, `clock-alt-symbolic`, "Edit Time") whose popover has two vertical `Gtk.SpinButton`s (hour 0–23, minute 0–59) around a ":" label, an `Adw.ToggleGroup` AM/PM (hidden under 24h), and a "Change Timezone" `Gtk.Button` with `Adw.ButtonContent` (`globe-symbolic`); two `Gtk.Adjustment`s |
| `gcal-date-selector.blp` + `.c` | `lib/date_selector.rb` | widget | `Gtk.Entry` (11 chars, `pan-down-symbolic` secondary icon) + `EventControllerFocus` + `Gtk.Popover` holding a `$GcalDateChooser` |
| `gcal-multi-choice.blp` + `.c` | `lib/multi_choice.rb` | widget | `Gtk.Box`, accessible-role `spin_button`; `down_button` (`back-button`, `circular`, `flat`, `pan-start-symbolic`), `ToggleButton` `button` (`flat`, `pill`, `popup`) with an `EventControllerKey` and a `Gtk.Stack` of two `Gtk.Label`s for the animated roll, `up_button` (`circular`, `flat`, `forward-button`, `pan-end-symbolic`); props `min-value`, `max-value`, `value`, `wrap`, `animate`, `category`, `popover`, the two button tooltips |
| `gcal-attendees-section.blp` + `.c` | `lib/attendees_section.rb` | section | `$GcalOrganizerRow` + two `$GcalAttendeeSummaryRow`s ("Participants" filtered to persons, "Resources" filtered to resources) |
| `gcal-attendee-summary-row.blp` + `.c` | `lib/attendee_summary_row.rb` | row | `Adw.ActionRow` (`property`), visible only when the filtered list is non-empty; count `Gtk.Label` (`participants-count-label`) and `open_details` `Gtk.Image` (`go-next-symbolic`) as the activatable widget |
| `gcal-attendee-details-page.blp` + `.c` | `lib/attendee_details_page.rb` | page | `Adw.NavigationPage` "Participants"; `Adw.PreferencesPage` with five `Adw.PreferencesGroup`s — Accepted, Tentative, Declined, Delegated, Not responded — each visible only when its `Gtk.FilterListModel` is non-empty **(empty states)**; rows are `$GcalAttendeeRow` (**repeater**) |
| `gcal-attendee-row.blp` + `.c` | `lib/attendee_row.rb` | row | `Adw.ActionRow` with a right-click `GestureClick`, a role `Gtk.Label` (`dimmed`), and a `Gtk.PopoverMenu` context menu with one item "Copy email" → action `attendee-row.copy-email` |
| `gcal-organizer-row.blp` + `.c` | `lib/organizer_row.rb` | row | `Adw.ActionRow` "Organizer" (`property`) with a right-click `GestureClick` and a context menu "Copy email" → `organizer-row.copy-email` |
| `gcal-reminders-section.blp` + `.c` | `lib/reminders_section.rb` | section | `alarms_listbox` (`boxed-list`) with an `Adw.ButtonRow` "Add Reminder" (`add-reminder-symbolic`); a `Gtk.Popover` (`menu`, `alarms`, 175 wide) of ten `Gtk.ModelButton`s: Event start, 5/10/15/30 Minutes, 1 Hour, 1/2/3 Days, 1 Week; rows are `$GcalAlarmRow` (**repeater**) |
| `gcal-alarm-row.blp` + `.c` | `lib/alarm_row.rb` | row | `Adw.ActionRow` with a `remove_button` (`flat`, `edit-delete-symbolic`, "Remove Alarm") |
| `gcal-notes-section.blp` + `.c` | `lib/notes_section.rb` | section | `Adw.PreferencesRow` (`notes-section`, `entry`) with a `GestureClick` focusing the text view; `Gtk.Overlay` (css-name `box`, class `header`) over two `Adw.Bin`s (`editable-area`): a `placeholder` `Gtk.Label` "Notes" (`dimmed`, `placeholder`) shown when empty **(empty state)**, and the `notes_text` `Gtk.TextView` (word-char wrap) |
| `gcal-time-zone-dialog.blp` + `.c` | `lib/time_zone_dialog.rb` | dialog | `Adw.Dialog` "Select Timezone" 400×540; `Adw.HeaderBar`; `Gtk.SearchEntry` "Search Locations" in a toolbar `Adw.Bin` (`search-changed`, `stop-search`); `Gtk.Stack` with `Adw.StatusPage` `empty_search` ("Search for a Timezone", `loupe-large-symbolic`) **(empty state)** and an `Adw.PreferencesPage` whose `listbox` (`boxed-list`) holds `$GcalTimeZoneDialogRow`s (**repeater**) |
| `gcal-time-zone-dialog-row.blp` + `.c` | `lib/time_zone_dialog_row.rb` | row | activatable `Adw.ActionRow` (`property`) |

---

## 6. Calendar management (`src/gui/calendar-management/`)

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `gcal-calendar-management-dialog.blp` + `.c` | `lib/calendar_management_dialog.rb` | dialog | `Adw.Dialog` "Calendar Settings", 500 content width, min 360×500; `Adw.NavigationView` (`popped`) hosting the three pages |
| `gcal-calendar-management-page.c/.h` | `lib/calendar_management_page.rb` | interface / mixin | `GcalCalendarManagementPage`: `activate`, `deactivate`, `get_title`, prop `context` |
| `gcal-calendars-page.blp` + `.c` | `lib/calendars_page.rb` | page | `Adw.NavigationPage` "Calendars" (tag `calendars`); `Adw.ToastOverlay`; `Adw.ToolbarView` + `Adw.HeaderBar`; `Adw.PreferencesPage` → `Adw.PreferencesGroup` → `listbox` (`calendars-list`, `boxed-list`, `row-activated`); bottom `Adw.Clamp` with a `boxed-list` `Gtk.ListBox` holding `Adw.ButtonRow` "_Add Calendar" (`go-next-symbolic`, managed `<Ctrl>n` shortcut); rows are `calendar-row.blp` (**repeater**) |
| `calendar-row.blp` | folded into `lib/calendars_page.rb` (or `lib/calendar_management_row.rb`) | row | standalone `Adw.ActionRow`, activatable: colour `Gtk.Image` (`calendar-color-image`, 24 px), `read_only_icon` (`changes-prevent-symbolic`, "Read-Only Calendar"), `Gtk.Switch` ("Display Calendar"), `go-next-symbolic` `Gtk.Image` (a11y label "Edit calendar") |
| `gcal-edit-calendar-page.blp` + `.c` | `lib/edit_calendar_page.rb` | page | `Adw.NavigationPage` "Edit Calendar" (tag `edit-calendar`); `Adw.WindowTitle` bound to the name entry; `account_row` (`property`) with a `settings_button` (`flat`, `external-link-symbolic`, "Open in Settings"); `calendar_url_row` "Location" (`property`); `Adw.EntryRow` "Calendar Name"; "Color" `Adw.ActionRow` + `Gtk.ColorDialogButton` (no alpha); `Adw.SwitchRow` "_Display Calendar"; `Adw.ButtonRow` "_Export Calendar" and `Adw.ButtonRow` "_Remove Calendar" (`destructive-action`) |
| `gcal-new-calendar-page.blp` + `.c` | `lib/new_calendar_page.rb` | page | `Adw.NavigationPage` "New Calendar" (tag `new-calendar`); group "Create a Local Calendar" with an `Adw.EntryRow` name and a `Gtk.ColorDialogButton`; group "Connect to an Online Calendar" with an explanatory `Gtk.Label`, a URL `Gtk.Entry` (`https://example.com/calendar.ics`, purpose url), a `Gtk.Revealer` `web_sources_revealer` (slide-down) containing a "Calendars" heading `Gtk.Label` and `web_sources_listbox` (`calendar-list`), and a markup `Gtk.Label` linking to the GOA settings; `add_button` "Add Calendar" (`pill`, `suggested-action`, insensitive until valid); standalone `Adw.MessageDialog` `credentials_dialog` "Credentials" with `Adw.EntryRow` "User" + `Adw.PasswordEntryRow` "Password" and `_Cancel` / `_Connect` responses **(auth/error state)** |
| `src/utils/gcal-source-discoverer.c/.h` | `lib/source_discoverer.rb` | helper | probes a URL for CalDAV/Webcal sources; drives the revealer and the credentials dialog |

---

## 7. Importer (`src/gui/importer/`)

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `gcal-import-dialog.blp` + `.c` | `lib/import_dialog.rb` | dialog | `Adw.Dialog` "Import Files…", follows content size, min height 294; `Adw.ToastOverlay`; `Adw.HeaderBar` with `cancel_button` "_Cancel" (`sheet.close`) and `import_button` "_Import" (`suggested-action`); `Adw.Clamp` → `calendars_box` with a `$GcalCalendarComboRow` "C_alendar" and `files_group` whose placeholder is an `Adw.Spinner` **(loading state)**; `Gtk.SizeGroup` `title_sizegroup`; `Escape` → `sheet.close`; rows are `$GcalImportFileRow` (**repeater**) |
| `gcal-import-file-row.blp` + `.c` | `lib/import_file_row.rb` | row | `Adw.Bin` + `events_listbox` (`boxed-list`); builds one `Adw.ActionRow` per event in the ICS file, with a checkbox-style selection |
| `gcal-importer.c/.h` | `lib/importer.rb` | helper | async ICS parsing, "Not an ICS file" errors feeding the window toasts |

---

## 8. Non-GUI support that the port needs behind the components

Not user-facing on their own, but every view and dialog above depends on them.
Listed so the port has the whole dependency set.

| Upstream | Target | Kind |
|---|---|---|
| `src/core/gcal-context.c` | `lib/context.rb` | model |
| `src/core/gcal-manager.c` | `lib/manager.rb` | model |
| `src/core/gcal-calendar.c` | `lib/calendar.rb` | model |
| `src/core/gcal-calendar-monitor.c` | `lib/calendar_monitor.rb` | model |
| `src/core/gcal-event.c` | `lib/event.rb` | model |
| `src/core/gcal-event-list.c` | `lib/event_list.rb` | model |
| `src/core/gcal-event-attendee.c` | `lib/event_attendee.rb` | model |
| `src/core/gcal-event-organizer.c` | `lib/event_organizer.rb` | model |
| `src/core/gcal-recurrence.c` | `lib/recurrence.rb` | model |
| `src/core/gcal-range.c`, `gcal-range-tree.c` | `lib/range.rb`, `lib/range_tree.rb` | model |
| `src/core/gcal-timeline.c`, `gcal-timeline-subscriber.c` | `lib/timeline.rb`, `lib/timeline_subscriber.rb` | model |
| `src/core/gcal-clock.c`, `gcal-timer.c` | `lib/clock.rb`, `lib/timer.rb` | model |
| `src/core/gcal-time-zone-monitor.c` | `lib/time_zone_monitor.rb` | model |
| `src/core/gcal-shell-search-provider.c` | `lib/shell_search_provider.rb` | D-Bus service |
| `src/search/gcal-search-engine.c`, `gcal-search-model.c`, `gcal-search-hit.c`, `gcal-search-hit-event.c` | `lib/search_engine.rb`, `lib/search_model.rb`, `lib/search_hit.rb`, `lib/search_hit_event.rb` | model |
| `src/weather/gcal-weather-service.c`, `gcal-weather-info.c` | `lib/weather_service.rb`, `lib/weather_info.rb` | service |
| `src/utils/gcal-date-time-utils.c`, `gcal-gui-utils.c`, `gcal-utils.c` | `lib/date_time_utils.rb`, `lib/gui_utils.rb`, `lib/utils.rb` | helper |
| `data/org.gnome.calendar.gschema.xml.in` | `lib/settings.rb` | settings |
| `src/theme/style.css`, `src/theme/events.css` | `lib/style.rb` (inline `Gtk::CssProvider`) | stylesheet |
| `src/gui/icons/*.svg` (18 icons) | `data/icons/` + a resource loader | assets |
| `po/*.po` (78 locales), `po/POTFILES.in` (71 files) | translation catalogue | i18n |

CSS classes the stylesheets define that the port must keep: `blurred`,
`calendar-list`, `calendars-list`, `drop-overlay-area`, `drop-target`,
`notes-section`, `participants-count-label`, `sidebar-pane`,
`week-main-content`, `content`, `edge`, `month-view`, `slanted`,
`slanted-start`, `slanted-end`.

GSettings keys: `window-maximized`, `window-size`, `active-view`,
`weather-settings`, `week-view-zoom-level`.

Custom icons shipped in the gresource: `add-reminder-symbolic`,
`calendar-agenda-symbolic`, `calendar-month-symbolic`,
`calendar-today-symbolic`, `calendar-week-symbolic`, `check-plain-symbolic`,
`checkmark-small-symbolic`, `clock-alt-symbolic`, `edit-symbolic`,
`external-link-symbolic`, `eye-not-looking-symbolic`, `globe-symbolic`,
`info-outline-symbolic`, `loupe-large-symbolic`, `map-symbolic`,
`share-symbolic`.

---

## Port status, component by component

`✓` exists on `ruby`, `·` absent. Order is the order a user meets them.

| # | Upstream | Target | Kind | Present |
|---:|---|---|---|:---:|
| 1 | `src/gui/gcal-application.c` | `lib/main.rb` | application | ✓ |
| 2 | `src/gui/gcal-window.blp` + `.c` | `lib/window.rb` | window | ✓ |
| 3 | `src/gui/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | dialog | ✓ |
| 4 | `src/gui/common/gcal-date-chooser.blp` + `.c` | `lib/date_chooser.rb` | widget | ✓ |
| 5 | `src/gui/common/gcal-date-chooser-day.blp` + `.c` | `lib/date_chooser_day.rb` | widget | ✓ |
| 6 | `src/gui/common/gcal-calendar-row.blp` + `.c` | `lib/calendar_row.rb` | row | ✓ |
| 7 | `src/gui/common/gcal-calendar-combo-row.blp` + `.c` | `lib/calendar_combo_row.rb` | row | · |
| 8 | `src/gui/views/gcal-view.c` (+ `-private.h`) | `lib/view.rb` | interface / mixin | ✓ |
| 9 | `src/gui/views/gcal-month-view.blp` + `.c` | `lib/month_view.rb` | view | ✓ |
| 10 | `src/gui/views/gcal-month-view-row.c` | `lib/month_view_row.rb` | widget (code-built) | · |
| 11 | `src/gui/views/gcal-month-cell.blp` + `.c` | `lib/month_cell.rb` | widget | ✓ |
| 12 | `src/gui/views/gcal-month-popover.blp` + `.c` | `lib/month_popover.rb` | popover | ✓ |
| 13 | `src/gui/views/gcal-week-view.blp` + `.c` (+ `-common.c`) | `lib/week_view.rb` | view | · |
| 14 | `src/gui/views/gcal-week-header.blp` + `.c` | `lib/week_header.rb` | widget | · |
| 15 | `src/gui/views/gcal-week-grid.c` | `lib/week_grid.rb` | widget (code-built) | · |
| 16 | `src/gui/views/gcal-week-hour-bar.c` | `lib/week_hour_bar.rb` | widget (code-built) | · |
| 17 | `src/gui/views/gcal-agenda-view.blp` + `.c` | `lib/agenda_view.rb` | view | ✓ |
| 18 | `src/gui/views/gcal-agenda-view-day-row.blp` + `.c` | `lib/agenda_view_day_row.rb` | row | ✓ |
| 19 | `src/gui/views/gcal-agenda-view-day.c` | `lib/agenda_view_day.rb` | model object | ✓ |
| 20 | `src/gui/gcal-event-widget.blp` + `.c` | `lib/event_widget.rb` | widget | ✓ |
| 21 | `src/gui/gcal-event-widget-pool.c` | `lib/event_widget_pool.rb` | helper | · |
| 22 | `src/gui/gcal-event-popover.blp` + `.c` | `lib/event_popover.rb` | popover | · |
| 23 | `src/gui/gcal-meeting-row.blp` + `.c` | `lib/meeting_row.rb` | row | · |
| 24 | `src/gui/gcal-quick-add-popover.blp` + `.c` | `lib/quick_add_popover.rb` | popover | ✓ |
| 25 | `src/gui/gcal-search-button.blp` + `.c` | `lib/search_button.rb` | widget | · |
| 26 | `src/gui/gcal-sync-indicator.blp` + `.c` | `lib/sync_indicator.rb` | widget | ✓ |
| 27 | `src/gui/gcal-calendar-navigation-button.blp` + `.c` | `lib/calendar_navigation_button.rb` | widget | · |
| 28 | `src/gui/gcal-calendar-list.blp` + `.c` | `lib/calendar_list.rb` | widget | ✓ |
| 29 | `src/gui/gcal-weather-settings.blp` + `.c` | `lib/weather_settings.rb` | menu popover content | · |
| 30 | `src/gui/gcal-drop-overlay.c` | `lib/drop_overlay.rb` | widget (code-built) | · |
| 31 | `src/gui/gcal-fading-label.c` | `lib/fading_label.rb` | widget (code-built) | · |
| 32 | `src/gui/gcal-overflow-bin.c` + `-layout.c` | `lib/overflow_bin.rb` | widget + layout manager | · |
| 33 | `src/gui/gcal-bidi.c` | `lib/bidi.rb` | helper | · |
| 34 | `src/gui/event-editor/gcal-event-editor-dialog.blp` + `.c` | `lib/event_editor_dialog.rb` | dialog | · |
| 35 | `src/gui/event-editor/gcal-event-editor-section.c` | `lib/event_editor_section.rb` | interface / mixin | · |
| 36 | `src/gui/event-editor/gcal-summary-section.blp` + `.c` | `lib/summary_section.rb` | section | · |
| 37 | `src/gui/event-editor/gcal-schedule-section.blp` + `.c` | `lib/schedule_section.rb` | section | · |
| 38 | `src/gui/event-editor/gcal-event-schedule.c` | `lib/event_schedule.rb` | model | · |
| 39 | `src/gui/event-editor/gcal-date-chooser-row.blp` + `.c` | `lib/date_chooser_row.rb` | row | · |
| 40 | `src/gui/event-editor/gcal-date-time-chooser.blp` + `.c` | `lib/date_time_chooser.rb` | group | · |
| 41 | `src/gui/event-editor/gcal-date-selector.blp` + `.c` | `lib/date_selector.rb` | widget | · |
| 42 | `src/gui/event-editor/gcal-multi-choice.blp` + `.c` | `lib/multi_choice.rb` | widget | ✓ |
| 43 | `src/gui/event-editor/gcal-attendees-section.blp` + `.c` | `lib/attendees_section.rb` | section | · |
| 44 | `src/gui/event-editor/gcal-attendee-summary-row.blp` + `.c` | `lib/attendee_summary_row.rb` | row | · |
| 45 | `src/gui/event-editor/gcal-attendee-details-page.blp` + `.c` | `lib/attendee_details_page.rb` | page | · |
| 46 | `src/gui/event-editor/gcal-attendee-row.blp` + `.c` | `lib/attendee_row.rb` | row | · |
| 47 | `src/gui/event-editor/gcal-organizer-row.blp` + `.c` | `lib/organizer_row.rb` | row | · |
| 48 | `src/gui/event-editor/gcal-reminders-section.blp` + `.c` | `lib/reminders_section.rb` | section | · |
| 49 | `src/gui/event-editor/gcal-alarm-row.blp` + `.c` | `lib/alarm_row.rb` | row | · |
| 50 | `src/gui/event-editor/gcal-notes-section.blp` + `.c` | `lib/notes_section.rb` | section | · |
| 51 | `src/gui/event-editor/gcal-time-zone-dialog.blp` + `.c` | `lib/time_zone_dialog.rb` | dialog | · |
| 52 | `src/gui/event-editor/gcal-time-zone-dialog-row.blp` + `.c` | `lib/time_zone_dialog_row.rb` | row | · |
| 53 | `src/gui/calendar-management/gcal-calendar-management-dialog.blp` + `.c` | `lib/calendar_management_dialog.rb` | dialog | · |
| 54 | `src/gui/calendar-management/gcal-calendar-management-page.c` | `lib/calendar_management_page.rb` | interface / mixin | · |
| 55 | `src/gui/calendar-management/gcal-calendars-page.blp` + `.c` | `lib/calendars_page.rb` | page | · |
| 56 | `src/gui/calendar-management/calendar-row.blp` | `lib/calendar_management_row.rb` | row | · |
| 57 | `src/gui/calendar-management/gcal-edit-calendar-page.blp` + `.c` | `lib/edit_calendar_page.rb` | page | · |
| 58 | `src/gui/calendar-management/gcal-new-calendar-page.blp` + `.c` | `lib/new_calendar_page.rb` | page | · |
| 59 | `src/utils/gcal-source-discoverer.c` | `lib/source_discoverer.rb` | helper | · |
| 60 | `src/gui/importer/gcal-import-dialog.blp` + `.c` | `lib/import_dialog.rb` | dialog | · |
| 61 | `src/gui/importer/gcal-import-file-row.blp` + `.c` | `lib/import_file_row.rb` | row | · |
| 62 | `src/gui/importer/gcal-importer.c` | `lib/importer.rb` | helper | · |

62 user-facing components, 18 present.

### Supporting files

| Upstream | Target | Present |
|---|---|:---:|
| `src/core/gcal-context.c` | `lib/context.rb` | ✓ |
| `src/core/gcal-manager.c` | `lib/manager.rb` | ✓ |
| `src/core/gcal-calendar.c` | `lib/calendar.rb` | ✓ |
| `src/core/gcal-calendar-monitor.c` | `lib/calendar_monitor.rb` | · |
| `src/core/gcal-event.c` | `lib/event.rb` | ✓ |
| `src/core/gcal-event-list.c` | `lib/event_list.rb` | ✓ |
| `src/core/gcal-event-attendee.c` | `lib/event_attendee.rb` | ✓ |
| `src/core/gcal-event-organizer.c` | `lib/event_organizer.rb` | ✓ |
| `src/core/gcal-recurrence.c` | `lib/recurrence.rb` | ✓ |
| `src/core/gcal-range.c` | `lib/range.rb` | ✓ |
| `src/core/gcal-range-tree.c` | `lib/range_tree.rb` | ✓ |
| `src/core/gcal-timeline.c` | `lib/timeline.rb` | · |
| `src/core/gcal-timeline-subscriber.c` | `lib/timeline_subscriber.rb` | · |
| `src/core/gcal-clock.c` | `lib/clock.rb` | ✓ |
| `src/core/gcal-timer.c` | `lib/timer.rb` | ✓ |
| `src/core/gcal-time-zone-monitor.c` | `lib/time_zone_monitor.rb` | · |
| `src/core/gcal-shell-search-provider.c` | `lib/shell_search_provider.rb` | · |
| `src/search/gcal-search-engine.c` | `lib/search_engine.rb` | · |
| `src/search/gcal-search-model.c` | `lib/search_model.rb` | · |
| `src/search/gcal-search-hit.c` | `lib/search_hit.rb` | · |
| `src/search/gcal-search-hit-event.c` | `lib/search_hit_event.rb` | · |
| `src/weather/gcal-weather-service.c` | `lib/weather_service.rb` | · |
| `src/weather/gcal-weather-info.c` | `lib/weather_info.rb` | · |
| `src/utils/gcal-date-time-utils.c` | `lib/date_time_utils.rb` | ✓ |
| `src/utils/gcal-gui-utils.c` | `lib/gui_utils.rb` | · |
| `src/utils/gcal-utils.c` | `lib/utils.rb` | ✓ |
| `data/org.gnome.calendar.gschema.xml.in` | `lib/settings.rb` | ✓ |
| `src/theme/style.css` + `events.css` | `lib/style.rb` | ✓ |
| `src/gui/icons/*.svg` (16 icons) | `data/icons/` + loader | · |
| `po/*.po` (78 locales) | translation catalogue | · |

28 supporting files, 16 present.

---

## Summary

| Area | Components | Present on `ruby` |
|---|---:|---:|
| Application + window + shortcuts dialog | 3 | 3 |
| Shared widgets (`src/gui/common/`) | 4 | 3 |
| Views (`src/gui/views/`) | 12 | 7 |
| Event display widgets (`src/gui/`) | 14 | 4 |
| Event editor (`src/gui/event-editor/`) | 19 | 1 |
| Calendar management (`src/gui/calendar-management/`) | 7 | 0 |
| Importer (`src/gui/importer/`) | 3 | 0 |
| **User-facing total** | **62** | **18** |
| Supporting models / services / helpers | 28 | 16 |

Full parity is 62 user-facing components plus 28 supporting files. The shell,
the month view, the agenda view, the sidebar and the quick-add popover are
done; 44 user-facing components remain.

## Remaining port order

1. `lib/month_view_row.rb`, `lib/overflow_bin.rb`, `lib/fading_label.rb`, `lib/event_widget_pool.rb`, `lib/bidi.rb` — the layout primitives the month and week views want underneath them.
2. `lib/event_popover.rb` + `lib/meeting_row.rb` — clicking an event currently has nowhere to go.
3. `lib/calendar_navigation_button.rb` — the header-bar date chooser, reusing `lib/date_chooser.rb`.
4. The week view: `lib/week_hour_bar.rb` → `lib/week_grid.rb` → `lib/week_header.rb` → `lib/week_view.rb`. This fills the one empty page in the window's view stack.
5. The event editor, section by section: `lib/event_editor_section.rb` → `lib/event_editor_dialog.rb` → summary → `lib/calendar_combo_row.rb` → `lib/event_schedule.rb` + `lib/date_selector.rb` + `lib/date_chooser_row.rb` + `lib/date_time_chooser.rb` + schedule → reminders + `lib/alarm_row.rb` → notes → attendees (`lib/organizer_row.rb`, `lib/attendee_row.rb`, `lib/attendee_summary_row.rb`, `lib/attendees_section.rb`, `lib/attendee_details_page.rb`) → `lib/time_zone_dialog.rb` + its row.
6. Calendar management: `lib/calendar_management_page.rb` → `lib/calendars_page.rb` + `lib/calendar_management_row.rb` → `lib/edit_calendar_page.rb` → `lib/new_calendar_page.rb` + `lib/source_discoverer.rb` → `lib/calendar_management_dialog.rb`.
7. The importer: `lib/importer.rb` → `lib/import_file_row.rb` → `lib/import_dialog.rb`, plus `lib/drop_overlay.rb` for the window's drop target.
8. Search: `lib/search_hit.rb`, `lib/search_hit_event.rb`, `lib/search_model.rb`, `lib/search_engine.rb`, `lib/search_button.rb`, then `lib/shell_search_provider.rb`.
9. Weather: `lib/weather_info.rb`, `lib/weather_service.rb`, `lib/weather_settings.rb`.
10. The leftovers: `lib/calendar_monitor.rb`, `lib/timeline.rb`, `lib/timeline_subscriber.rb`, `lib/time_zone_monitor.rb`, `lib/gui_utils.rb`, the 16 custom icons, and the translation catalogue.
