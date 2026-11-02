# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists every keyboard shortcut the app binds, in the three
# sections upstream groups them into.
#
# Upstream has no source file for this — it is a standalone
# Adw.ShortcutsDialog in a blueprint, loaded by libadwaita's own
# app.shortcuts action. The port builds the same dialog by hand and presents
# it from the same action.
#
# Ported from upstream's src/gui/shortcuts-dialog.blp.
#
class ShortcutsDialog
  SECTIONS = {
    'General'    => [
      ['Open Main Menu', 'F10'],
      ['Toggle Sidebar', 'F9'],
      ['New Event', '<Primary>N'],
      ['Manage Calendars', 'F8 <Ctrl><Alt>m'],
      ['Synchronize Calendars', 'F5 <Ctrl>r'],
      ['Close Window', '<Primary>Q <Primary>W'],
      ['Search', '<Primary>F'],
      ['Show Help', 'F1'],
      ['Shortcuts', '<Primary>question'],
    ],
    'Navigation' => [
      ['Go Back', '<Alt>Left Page_Up'],
      ['Go Forward', '<Alt>Right Page_Down'],
      ['Show Today', '<Alt>Down <Primary>T Home'],
      ['Next View', '<Primary>Page_Down'],
      ['Previous View', '<Primary>Page_Up'],
    ],
    'View'       => [
      ['Month View', '<Alt>1'],
      ['Week View', '<Alt>2'],
    ],
  }.freeze

  # Assembles the widget tree once; a second call is a no-op, which is what
  # lets a caller ask for the built dialog without caring whether it already
  # exists.
  def build
    unless @assembled
      @assembled = assemble
    end
    dialog
  end

  def assemble
    dialog.tap do |widget|
      SECTIONS.each do |title, items|
        widget.add(build_section(title, items))
      end
    end
  end

  def widget = build

  # Presents the dialog over @parent, as libadwaita's own shortcuts action
  # does.
  def present(parent)
    build.present(parent)
    self
  end

  def dialog = @dialog ||= Adwaita::ShortcutsDialog.new

  private

    def build_section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |item_title, accelerator| section.add(Adwaita::ShortcutsItem.new(item_title, accelerator)) }
      end
    end
end
