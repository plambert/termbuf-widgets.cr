require "../../router"
require "../../widget"

module TermBuf::Widgets
  # Two spellings of the same marks, and the rule for choosing between them.
  #
  # A box-drawing tick is one cell wide on a terminal that measures it the way
  # the standard says and two on one that does not, and a widget laid out for
  # the first and drawn on the second overflows by a cell per mark. Rather than
  # guess, the marks are measured under the policy the tree was built with and
  # the ASCII spelling is used whenever the pretty one does not come out at one
  # cell each.
  module Glyphs
    extend self

    # Whether every one of *glyphs* measures exactly one cell under *policy*.
    def single_cell?(glyphs : Enumerable(String), policy : Unicode::WidthPolicy) : Bool
      glyphs.all? { |glyph| Unicode.string_width(glyph, policy) == 1 }
    end

    # *preferred* when every glyph in it measures one cell under *policy*, and
    # *fallback* otherwise.
    def choose(preferred : Enumerable(String), fallback : Enumerable(String),
               policy : Unicode::WidthPolicy) : Enumerable(String)
      single_cell?(preferred, policy) ? preferred : fallback
    end
  end

  # What a widget that answers the keyboard and the pointer needs and `Widget`
  # does not give it.
  #
  # Two things live here. Knowing whether the keyboard is on this widget, which
  # a button needs in order to draw itself differently, and turning a press and
  # a release into one click, which every clickable widget needs and none
  # should write twice.
  module Interactive
    # Whether the pointer went down on this widget and has not come up again.
    getter? held : Bool = false

    # Whether the keyboard is on this widget.
    #
    # A widget has no link to the focus stack, so this finds the router the way
    # `Widget#emit` finds its mailbox: by walking up to whatever the root
    # carries. A tree drawn without a router — which is what a layout spec
    # does — has no focus at all, and everything in it answers `false`.
    def focused? : Bool
      router = routed_by
      return false unless router

      held = router.focus.current
      !held.nil? && held.same?(self)
    end

    # Puts the keyboard on this widget, answering whether it went.
    def take_focus(context : Context) : Bool
      context.focus.focus self
    end

    # The router dispatching into this widget's tree, or `nil` outside one.
    def routed_by : Router?
      node : Widget? = self
      while node
        box = node.mailbox
        return box if box.is_a? Router

        node = node.parent
      end

      nil
    end

    # Turns a press and a release inside this widget into one click.
    #
    # The press captures the pointer, so the release arrives here wherever it
    # happened; a release outside the widget is a click abandoned rather than a
    # click made, which is what dragging off a button means everywhere else.
    def clicked(event : Events::Mouse, context : Context, & : -> Nil) : Nil
      return unless event.button.left?

      case event.action
      in .press?   then start_click event, context
      in .motion?  then context.consume if @held
      in .release? then finish_click(event, context) { yield }
      end
    end

    private def start_click(event : Events::Mouse, context : Context) : Nil
      return unless frame.contains? event.x, event.y

      @held = true
      context.capture self
      context.consume
    end

    private def finish_click(event : Events::Mouse, context : Context, & : -> Nil) : Nil
      return unless @held

      @held = false
      context.release
      context.consume
      yield if frame.contains? event.x, event.y
    end
  end

  # Moving the keyboard between the children of one widget.
  #
  # A group of related controls is moved between by the arrows that run along
  # it, while tab still moves between the groups themselves. Wrapping at either
  # end is what makes the group a closed set: tab is the way out of it, and an
  # arrow that stopped dead at the last child would leave no way back to the
  # first except tabbing through everything else on the screen.
  module Stepping
    # The children the arrows move between, in order.
    #
    # Whatever can take the keyboard, which leaves out a disabled control
    # without anything here having to know what disabled means.
    def stepped : Array(Widget)
      children.select &.focusable?
    end

    # Moves the keyboard *step* places along `#stepped`, wrapping at either
    # end. Does nothing when the keyboard is somewhere else entirely.
    def step_focus(context : Context, step : Int32) : Nil
      among = stepped
      return if among.empty?

      held = context.focus.current
      position = held ? among.index(&.same?(held)) : nil
      return unless position

      context.focus.focus among[(position + step) % among.size]
    end

    # The two arrows that run along *direction*, bound to moving between the
    # children. The arrows across it are left to whatever is outside.
    def arrow_keymap(direction : Layout::Direction) : Bindings
      back, on = case direction
                 in .row?    then {"Left", "Right"}
                 in .column? then {"Up", "Down"}
                 end

      Bindings.build do |map|
        map.bind Key.parse(back), "the one before",
          ->(context : Context) { step_focus context, -1; nil }
        map.bind Key.parse(on), "the one after",
          ->(context : Context) { step_focus context, 1; nil }
      end
    end
  end
end
