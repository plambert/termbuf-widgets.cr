require "./keymap/keymap"
require "./widget"

module TermBuf::Widgets
  # Which widget has the keyboard, and which ones it can be handed to next.
  module Focus
    # One layer: a subtree, the widgets in it that can take focus, and the
    # keymap that layer adds under them.
    #
    # A dialog is a scope of its own. While it is on top, tab moves inside it
    # and nowhere else, and a key that nothing in it claims stops at its root
    # rather than reaching the window behind.
    class Scope
      # The subtree this layer covers, and the barrier a key stops at.
      getter root : Widget

      # Everything focusable under `#root`, in the order tab visits them.
      getter ring = [] of Widget

      # The keys this layer answers after every widget in the chain has
      # declined them.
      property keymap : Bindings?

      # Where in the ring focus is sitting.
      property index : Int32 = 0

      def initialize(@root : Widget, @keymap : Bindings? = nil)
        rebuild
      end

      # The widget with the keyboard, or `nil` when nothing in this layer can
      # take it.
      def current : Widget?
        @ring[@index]?
      end

      # Finds the focusable widgets again, keeping the keyboard where it is if
      # that widget is still one of them.
      #
      # Adding a widget, taking one out and hiding one are all layout
      # invalidations, so the flag that says a frame has to lay out again is
      # the same flag that says the ring is stale.
      def rebuild : Nil
        held = current
        @ring.clear
        gather @root

        @index = if held && (found = @ring.index(&.same?(held)))
                   found
                 else
                   @index.clamp 0, {@ring.size - 1, 0}.max
                 end
      end

      # Puts the keyboard on *widget*, if it is one of ours.
      def focus(widget : Widget) : Bool
        rebuild
        found = @ring.index &.same?(widget)
        return false unless found

        @index = found
        true
      end

      # Moves the keyboard on by *step* places, wrapping at either end.
      def step(step : Int32) : Widget?
        return if @ring.empty?

        @index = (@index + step) % @ring.size
        current
      end

      # Every focusable widget under *widget*, parents before children and
      # earlier siblings before later ones.
      #
      # A floating widget is walked like any other: a menu's items are part of
      # the tab order of whatever put the menu up, unless the menu was pushed
      # as a scope of its own.
      private def gather(widget : Widget) : Nil
        return if widget.hidden?

        @ring << widget if widget.focusable?
        widget.children.each { |child| gather child }
      end
    end

    # The layers, innermost last.
    #
    # There is always at least one: the application's own. Putting a dialog up
    # is `#push`, taking it down is `#pop`, and what was focused underneath is
    # still focused when it comes back.
    class Stack
      # Every layer, the application's first and the topmost last.
      getter scopes = [] of Scope

      def initialize(root : Widget, keymap : Bindings? = nil)
        @scopes << Scope.new(root, keymap)
      end

      # The layer keys and tab are answered by.
      def top : Scope
        @scopes.last
      end

      # The widget with the keyboard.
      def current : Widget?
        top.current
      end

      # Puts a layer on top, covering the one below.
      def push(root : Widget, keymap : Bindings? = nil) : Scope
        scope = Scope.new root, keymap
        @scopes << scope
        scope
      end

      # Takes the top layer off, giving the keyboard back to the one below,
      # where it was. The application's own layer is never popped.
      def pop : Scope?
        return if @scopes.size <= 1

        @scopes.pop
      end

      # Moves the keyboard to the next focusable widget in the top layer.
      def next : Widget?
        top.step 1
      end

      # Moves it to the previous one.
      def previous : Widget?
        top.step(-1)
      end

      # Puts the keyboard on *widget*, refusing one outside the top layer:
      # that is what makes a dialog modal.
      def focus(widget : Widget) : Bool
        top.focus widget
      end

      # Finds the focusable widgets of every layer again.
      def rebuild : Nil
        @scopes.each &.rebuild
      end
    end
  end
end
