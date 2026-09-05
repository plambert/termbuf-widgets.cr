require "../../message"
require "../panel"
require "./overlay"

module TermBuf::Widgets
  # A box hanging off a widget, which goes away when it is clicked past.
  #
  #     popover = Popover.new button, content: Label.new("what this does")
  #     popover.open app
  #
  # Where it lands is a `Layout::Anchor`: a point on the popover laid on top of
  # a point on the widget it hangs off. The default pair puts its top left
  # under the target's bottom left, which is where a menu goes, and
  # `Layout::Overflow::Flip` moves it above the target rather than off the
  # bottom of the screen.
  #
  # It is not modal: the rest of the screen keeps the keyboard and answers the
  # keys nothing in the popover claims. What it does take is the pointer, so a
  # click anywhere else takes the popover down instead of pressing whatever it
  # landed on — the same thing every menu everywhere does. `modal: true` pushes
  # a focus scope as well, for a popover that has to be answered.
  class Popover < Overlay
    # What the popover holds, or `nil` for one filled in later with `#add`.
    #
    # Named for what it is rather than for `Widget#content`, which is the box
    # the layout gave the popover and belongs to every widget there is.
    getter body : Widget?

    # The key that takes the popover down, or `nil` for one that has to be
    # clicked past.
    getter cancel_key : Key?

    def initialize(target : Widget? = nil,
                   content : Widget? = nil,
                   element : Layout::AttachPoint = Layout::AttachPoint::LeftTop,
                   parent : Layout::AttachPoint = Layout::AttachPoint::LeftBottom,
                   dx : Int32 = 0,
                   dy : Int32 = 0,
                   z : Int32 = Z::POPOVER,
                   overflow : Layout::Overflow = Layout::Overflow::Flip,
                   modal : Bool = false,
                   light_dismiss : Bool = true,
                   backdrop : Bool = false,
                   direction : Layout::Direction = Layout::Direction::Column,
                   width : Layout::Sizing = Layout::Sizing.fit,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   border : Border? = Border.plain,
                   style : Style? = nil,
                   cancel_key : Key? = Key.named(Key::Name::Escape))
      super modal: modal, light_dismiss: light_dismiss, backdrop: backdrop, z: z

      @cancel_key = cancel_key
      @direction = direction
      @width = width
      @height = height
      @padding = padding
      @border = border
      @style = style
      @floating = Layout::Floating.on target, element, parent,
        dx: dx, dy: dy, z: z, overflow: overflow

      @body = content
      add content if content

      self.keymap = popover_keymap
    end

    # The widget the popover hangs off, or `nil` for one pinned to the screen.
    def target : Widget?
      @floating.try &.anchor.target
    end

    # Hangs the popover off *target* instead, keeping the rest of the anchor.
    def target=(target : Widget?) : Widget?
      held = @floating
      return target unless held

      self.floating = Layout::Floating.new held.anchor.on(target), held.z,
        held.capture?, held.overflow
      target
    end

    # Where the popover's own corner sits, and which corner of the target it
    # sits on.
    def anchor_at(element : Layout::AttachPoint, parent : Layout::AttachPoint,
                  dx : Int32 = 0, dy : Int32 = 0) : Nil
      held = @floating
      return unless held

      anchor = held.anchor
      self.floating = Layout::Floating.new(
        Layout::Anchor.new(anchor.target, element, parent, dx, dy),
        held.z, held.capture?, held.overflow)
    end

    # Puts the popover up hanging off *target*.
    def open(app : App, target : Widget?) : self
      self.target = target
      open app
    end

    # The keys the popover answers, which reach it while the keyboard is
    # inside it and, for a modal one, wherever it is.
    private def popover_keymap : Bindings?
      cancel = @cancel_key
      return unless cancel

      Bindings.build do |map|
        map.bind cancel, "close", ->(_context : Context) { close }
      end
    end
  end
end
