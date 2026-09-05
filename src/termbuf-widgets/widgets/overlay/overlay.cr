require "../../app"
require "../../focus"
require "../../router"
require "../../widget"
require "../panel"

module TermBuf::Widgets
  # Something drawn over the screen rather than beside it, and the machinery
  # every one of those needs.
  #
  # An overlay is a float that is put up and taken down: a dialog, a menu, a
  # drawer. `#open` puts it in the tree, unhides it, optionally pushes a focus
  # scope so that it is the only thing the keyboard can reach, and moves the
  # keyboard into it; `#close` undoes all of that and gives the keyboard back
  # to whatever had it. The overlay stays where it was put, hidden, so opening
  # it a second time costs nothing and a message it emits on the way down still
  # has a parent to reach.
  #
  # Three floats make one overlay:
  #
  # * the overlay itself, at `#z`;
  # * a `Catcher` one below it, which is nowhere on the screen and everywhere
  #   in the hit test, so a click outside a modal overlay reaches the overlay
  #   rather than whatever it is covering;
  # * a `Backdrop` one below that, for an overlay that wants what is behind it
  #   dimmed.
  #
  # Both are children of the overlay, so they come and go with it and appear in
  # the chain an event walks up.
  abstract class Overlay < Panel
    # Where each kind of overlay sits, so that a menu opens over a drawer, a
    # dialog over both, and a toast over everything.
    module Z
      # A popover, a dropdown menu, a tooltip.
      POPOVER = 100

      # A drawer against an edge of the screen.
      DRAWER = 200

      # A dialog in the middle of it.
      DIALOG = 300

      # A toast, which has to be readable over whatever is asking for it.
      TOAST = 400
    end

    # A float with no size at all: nowhere on the screen, and everywhere in the
    # hit test.
    #
    # `Layout::Tree#hit` tries the floats from the top of the painting order
    # down, so a catcher sitting just under an overlay answers every point the
    # overlay itself did not, and nothing below it is ever reached. That is
    # what makes a modal overlay modal to the pointer as well as to the
    # keyboard, and what lets a menu hear the click that dismisses it.
    #
    # It draws nothing because there is nothing to draw: an empty rectangle is
    # skipped by the renderer before a view is even cut for it.
    class Catcher < Widget
      def initialize(z : Int32)
        @width = Layout::Sizing.fixed 0
        @height = Layout::Sizing.fixed 0
        @floating = Layout::Floating.on nil, z: z
      end

      # Which z it sits at, which is what an overlay changing its own has to
      # move.
      def z=(z : Int32) : Int32
        self.floating = Layout::Floating.on nil, z: z
        z
      end

      # Every point on the screen, which is the whole of what a catcher is
      # for.
      def at(x : Int32, y : Int32) : Widget?
        return if hidden?

        self
      end
    end

    # A screen-sized float that dims what is behind an overlay.
    #
    # The dimming is a `TermBuf::Blend`, so the colours already on the screen
    # decide what each cell comes out as: the default keeps them and adds
    # faint. It paints over what is behind it rather than tinting it, because
    # a drawing surface can be written to and not read: the glyphs behind a
    # backdrop go, and only their colours come through the blend.
    class Backdrop < Widget
      # Keeps the colours already on the screen and adds faint, which is a
      # backdrop that says "not this, the thing in front of it" without
      # choosing a palette on the application's behalf.
      DIM = Style.blend { |under, over| under.merge(over).faint }

      def initialize(z : Int32, wash : Blend? = DIM, style : Style? = nil)
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.grow
        @floating = Layout::Floating.on nil, z: z
        @wash = wash
        @style = style
      end

      # :ditto:
      def z=(z : Int32) : Int32
        self.floating = Layout::Floating.on nil, z: z
        z
      end
    end

    # Whether the overlay is up.
    getter? open : Bool = false

    # Whether the keyboard is held inside the overlay while it is up.
    #
    # A modal overlay pushes a focus scope of its own, so tab moves within it
    # and a key nothing in it claims stops at its root instead of reaching what
    # is behind. Changing this while the overlay is up does nothing until the
    # next time it is opened.
    property? modal : Bool

    # Whether a click that lands anywhere else takes the overlay down.
    property? light_dismiss : Bool

    # The app the overlay was opened on, or `nil` while it is down.
    getter app : App? = nil

    # The scope `#open` pushed, or `nil` for an overlay that is not modal.
    getter scope : Focus::Scope? = nil

    # What dims the screen behind the overlay, or `nil` for one that leaves it
    # alone.
    getter backdrop : Backdrop? = nil

    # What takes the clicks that land outside, or `nil` for an overlay that
    # lets them through.
    getter catcher : Catcher? = nil

    # Where the keyboard was before the overlay went up.
    @restore : Widget? = nil

    # Whether `#open` was the thing that put the overlay in the tree.
    @attached : Bool = false

    def initialize(modal : Bool = false, light_dismiss : Bool = false,
                   backdrop : Bool = false, z : Int32 = Z::POPOVER)
      @modal = modal
      @light_dismiss = light_dismiss
      @hidden = true
      self.backdrop = Backdrop.new z - 2 if backdrop
    end

    # Which z the overlay is painted at, and what its backdrop and catcher sit
    # below.
    def z : Int32
      @floating.try(&.z) || 0
    end

    # Dims the screen behind the overlay with *backdrop*, or stops dimming it
    # for `nil`.
    def backdrop=(backdrop : Backdrop?) : Backdrop?
      if held = @backdrop
        remove held
      end

      @backdrop = backdrop
      if backdrop
        backdrop.z = z - 2
        add backdrop
      end

      backdrop
    end

    # The keys the overlay answers while it is up, offered after every widget
    # in the chain has declined them.
    #
    # Only reached through a pushed scope, which is to say only while the
    # overlay is modal. A widget's own keymap is what answers a key in an
    # overlay that is not.
    def overlay_keymap : Bindings?
      @keymap
    end

    # Puts the overlay up on *app* and answers it.
    #
    # Adds it to the application's root if it is not in a tree already, which
    # is what lets one be built and opened without anywhere to put it first.
    def open(app : App) : self
      return self if @open

      @app = app
      install app
      @restore = app.focus.current

      self.hidden = false
      prepare app

      @scope = app.focus.push self, overlay_keymap if @modal
      focus_first app
      @open = true

      self
    end

    # Takes it down, giving the keyboard back to whatever had it.
    #
    # The overlay stays in the tree, hidden, so that a message emitted as it
    # closes still has a parent to reach and opening it again costs nothing.
    def close : Nil
      return unless @open

      @open = false
      app = @app
      @app = nil

      if @scope
        app.try &.focus.pop
        @scope = nil
      end

      self.hidden = true
      restore_focus app
    end

    # Takes the overlay out of the tree entirely, for one that will not be
    # opened again.
    def detach : Nil
      close
      return unless @attached

      @attached = false
      parent.try &.remove(self)
    end

    # Takes a click that landed outside the overlay.
    #
    # The event reached here through the `Catcher`, which is a child of the
    # overlay, so the chain walked up through it. Nothing is consumed: the
    # catcher already stopped the click from reaching whatever it looked like
    # it landed on, and an application watching for clicks it did not claim
    # should still see this one.
    def handle(event : Event, context : Context) : Nil
      return unless @open && @light_dismiss
      return unless event.is_a? Positioned
      return unless press? event
      return if frame.contains? event.x, event.y

      close
    end

    # What a subclass does between the overlay being unhidden and the keyboard
    # moving into it. Where a help overlay reads the bindings that were in
    # scope a moment ago.
    protected def prepare(app : App) : Nil
    end

    # Where the keyboard goes when the overlay opens, or `nil` to leave it on
    # the first thing that can take it.
    protected def initial_focus : Widget?
      nil
    end

    # Whether *event* is the press of a button rather than a release, a motion
    # or a wheel notch. A release is not a dismissal: it is the other half of
    # whatever click put the overlay up.
    private def press?(event : Positioned) : Bool
      return event.action.press? && !event.button.wheel? if event.is_a? Events::Mouse

      true
    end

    # Puts the overlay in the tree, and its catcher beside it.
    private def install(app : App) : Nil
      if parent.nil?
        app.root.add self
        @attached = true
      end

      needed = @modal || @light_dismiss
      held = @catcher

      if needed && held.nil?
        made = Catcher.new z - 1
        @catcher = made
        add made
      elsif !needed && held
        @catcher = nil
        remove held
      elsif held
        held.z = z - 1
      end

      @backdrop.try &.z=(z - 2)
    end

    # Moves the keyboard into the overlay.
    private def focus_first(app : App) : Nil
      wanted = initial_focus || first_focusable
      return unless wanted

      app.focus.focus wanted
    end

    # Gives the keyboard back to whatever had it, if that widget is still
    # somewhere it can be given to.
    private def restore_focus(app : App?) : Nil
      held = @restore
      @restore = nil
      return unless app && held
      return if held.hidden? || !app.tree.holds?(held)

      app.focus.focus held
    end

    # The first widget under the overlay that can take the keyboard, parents
    # before children.
    private def first_focusable : Widget?
      found : Widget? = nil

      each_in_tree do |widget|
        next if found || widget.hidden? || !widget.focusable?

        found = widget
      end

      found
    end
  end
end
