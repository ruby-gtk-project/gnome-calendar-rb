# frozen_string_literal: true

require 'adwaita'

# MultiChoice is the "‹ November ›" control: a back button, a label, and a
# forward button. The value it steps through is an integer; what the label
# shows for that integer is either an entry in `choices` or whatever a format
# block returns.
#
# The buttons go insensitive at the ends unless `wrap` is set, in which case
# stepping past an end comes round to the other and the `wrapped` handlers
# run — which is how the date chooser's month control rolls the year over.
#
# Ported from upstream's src/gui/event-editor/gcal-multi-choice.blp and
# src/gui/event-editor/gcal-multi-choice.c.
#
class MultiChoice
  attr_reader :value, :min_value, :max_value, :category

  def initialize(min_value: 0, max_value: 0, **options)
    @min_value = min_value
    @max_value = max_value
    @value = options.fetch(:value, min_value)
    @wrap = options.fetch(:wrap, false)
    @animate = options.fetch(:animate, false)
    @category = options.fetch(:category, '')
    @choices = options.fetch(:choices, [])
    @previous_tooltip = options.fetch(:previous_button_tooltip, '')
    @next_tooltip = options.fetch(:next_button_tooltip, '')
    @format_block = nil
    @popover = nil
    @previous_callback = nil
    @next_callback = nil
    @value_handlers = []
    @wrapped_handlers = []
  end

  # The assembled widget. Everything structural happens here; everything
  # cosmetic sits in the memoized methods below.
  def build
    box.tap do |container|
      container.append(down_button)
      container.append(button)
      container.append(up_button)

      down_button.tap do |widget|
        widget.signal_connect('clicked') { go_down }
      end

      up_button.tap do |widget|
        widget.signal_connect('clicked') { go_up }
      end

      button.tap do |widget|
        widget.child = stack

        stack.tap do |pages|
          pages.add_named(label1, 'label1')
          pages.add_named(label2, 'label2')
        end

        widget.add_controller(key_controller)
      end

      key_controller.tap do |controller|
        controller.signal_connect('key-pressed') do |_controller, keyval, _code, _state|
          on_key_pressed(keyval)
        end
      end

      apply_value(:none)
    end
  end

  def widget = build

  # Upstream's "notify::value": the block is handed the new value.
  def on_value_changed(&block)
    @value_handlers << block
    block
  end

  # Upstream's "wrapped" signal.
  def on_wrapped(&block)
    @wrapped_handlers << block
    block
  end

  # Upstream's gcal_multi_choice_set_format_callback(): the block turns a
  # value into the text the label shows.
  def format(&block)
    @format_block = block
    apply_value(:none)
    self
  end

  # Upstream's gcal_multi_choice_set_choices().
  def choices=(choices)
    @choices = choices
    apply_value(:none)
    choices
  end

  # Upstream's gcal_multi_choice_set_value(), clamped and silent when
  # unchanged.
  def value=(new_value)
    set_value(new_value, :none)
    @value
  end

  def min_value=(new_value)
    @min_value = new_value
    apply_value(:none)
    new_value
  end

  def max_value=(new_value)
    @max_value = new_value
    apply_value(:none)
    new_value
  end

  def wrap=(wrap)
    @wrap = wrap
    apply_value(:none)
    wrap
  end

  def wrap? = @wrap

  def animate=(animate)
    @animate = animate
    animate
  end

  def category=(category)
    @category = category
    category
  end

  # Upstream's "popover" property: with one set, the label itself becomes a
  # toggle that shows it.
  def popover=(popover)
    @popover = popover
    button.tap do |widget|
      widget.can_target = !popover.nil?
      unless popover.nil?
        widget.popover = popover
      end
    end
    popover
  end

  # Upstream's step callbacks, used by the combined month/year control whose
  # value is not a plain integer sequence.
  def step_callbacks(previous:, next_value:)
    @previous_callback = previous
    @next_callback = next_value
    self
  end

  # Upstream's go_up().
  def go_up
    stepped = step_up
    wrapped = false

    if stepped > @max_value && wrap?
      stepped = @min_value
      wrapped = true
    end

    if stepped <= @max_value
      set_value(stepped, :slide_left)
      if wrapped
        @wrapped_handlers.each(&:call)
      end
    end
    @value
  end

  # Upstream's go_down().
  def go_down
    stepped = step_down
    wrapped = false

    if stepped < @min_value && wrap?
      stepped = @max_value
      wrapped = true
    end

    if stepped >= @min_value
      set_value(stepped, :slide_right)
      if wrapped
        @wrapped_handlers.each(&:call)
      end
    end
    @value
  end

  def box
    @box ||= Gtk::Box.new(:horizontal, 6).tap do |container|
      container.accessible_role = :spin_button
    end
  end

  def down_button
    @down_button ||= Gtk::Button.new(icon_name: 'pan-start-symbolic').tap do |widget|
      widget.can_focus = false
      widget.tooltip_text = @previous_tooltip
      widget.add_css_class('back-button')
      widget.add_css_class('circular')
      widget.add_css_class('flat')
    end
  end

  def up_button
    @up_button ||= Gtk::Button.new(icon_name: 'pan-end-symbolic').tap do |widget|
      widget.can_focus = false
      widget.tooltip_text = @next_tooltip
      widget.add_css_class('forward-button')
      widget.add_css_class('circular')
      widget.add_css_class('flat')
    end
  end

  def button
    @button ||= Gtk::MenuButton.new.tap do |widget|
      widget.can_target = false
      widget.always_show_arrow = false
      widget.add_css_class('flat')
      widget.add_css_class('pill')
      widget.add_css_class('popup')
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.hexpand = true
      pages.vexpand = true
    end
  end

  def label1 = @label1 ||= Gtk::Label.new
  def label2 = @label2 ||= Gtk::Label.new
  def key_controller = @key_controller ||= Gtk::EventControllerKey.new

  private

    def step_up
      case @next_callback
      when nil then @value + 1
      else @next_callback.call(@value)
      end
    end

    def step_down
      case @previous_callback
      when nil then @value - 1
      else @previous_callback.call(@value)
      end
    end

    # Upstream's set_value(): clamp, bail out when unchanged, otherwise
    # animate the label across and notify.
    def set_value(new_value, transition)
      clamped = new_value.clamp(@min_value, @max_value)
      unless clamped == @value
        @value = clamped
        apply_value(transition)
        @value_handlers.each { |handler| handler.call(@value) }
      end
      @value
    end

    # Upstream's apply_value(): write the text into whichever of the two
    # labels is hidden, then slide to it.
    def apply_value(transition)
      name = 'label1'
      target = label1
      if stack.visible_child == label1
        name = 'label2'
        target = label2
      end

      target.text = value_string(@value)

      effective = transition
      unless @animate
        effective = :none
      end
      stack.set_visible_child_full(name, effective)

      down_button.sensitive = wrap? || @value > @min_value
      up_button.sensitive = wrap? || @value < @max_value
      self
    end

    # Upstream's get_value_string(): the format block, then the choices
    # list, then the number itself.
    def value_string(value)
      if @format_block
        @format_block.call(value)
      elsif value >= 0 && value < @choices.length
        @choices[value]
      else
        value.to_s
      end
    end

    # Upstream's key_pressed_cb(): Up/Right steps forward, Down/Left back,
    # and space or return opens the popover when there is one.
    def on_key_pressed(keyval)
      case keyval
      when Gdk::Keyval::KEY_Up, Gdk::Keyval::KEY_KP_Up, Gdk::Keyval::KEY_Right, Gdk::Keyval::KEY_KP_Right
        go_up
        true
      when Gdk::Keyval::KEY_Down, Gdk::Keyval::KEY_KP_Down, Gdk::Keyval::KEY_Left, Gdk::Keyval::KEY_KP_Left
        go_down
        true
      when Gdk::Keyval::KEY_space, Gdk::Keyval::KEY_KP_Space, Gdk::Keyval::KEY_Return, Gdk::Keyval::KEY_KP_Enter
        toggle_popover
      else false
      end
    end

    def toggle_popover
      case @popover
      when nil then false
      else
        button.popup
        true
      end
    end
end
