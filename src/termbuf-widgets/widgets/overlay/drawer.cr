require "../../message"
require "../panel"
require "./overlay"

module TermBuf::Widgets
  # A panel against one edge of the screen, which slides in and out.
  #
  #     drawer = Drawer.new Drawer::Edge::Right, size: 30, modal: true
  #     drawer.add Label.new("what is in the drawer")
  #     drawer.open app
  #
  # It fills the edge it is against and takes `#size` cells out from it: a left
  # or right drawer is as tall as the screen and *size* columns wide, a top or
  # bottom one as wide as the screen and *size* rows tall. Nothing here
  # animates: opening a drawer puts it where it goes, and a program wanting it
  # to slide moves `#size` a cell at a time between frames.
  #
  # `Escape` takes it down, and so does a click outside one told to dismiss
  # itself. Either way it says `Closed`.
  class Drawer < Overlay
    # Which edge the drawer is against.
    enum Edge
      Left
      Right
      Top
      Bottom

      # Whether the drawer runs down the screen rather than across it, which is
      # the axis its `Drawer#size` is measured on.
      def vertical? : Bool
        left? || right?
      end

      # The point on the drawer, and the point on the screen, that are laid on
      # top of each other.
      def attachment : {Layout::AttachPoint, Layout::AttachPoint}
        case self
        in .left?   then {Layout::AttachPoint::LeftTop, Layout::AttachPoint::LeftTop}
        in .right?  then {Layout::AttachPoint::RightTop, Layout::AttachPoint::RightTop}
        in .top?    then {Layout::AttachPoint::LeftTop, Layout::AttachPoint::LeftTop}
        in .bottom? then {Layout::AttachPoint::LeftBottom, Layout::AttachPoint::LeftBottom}
        end
      end
    end

    # The drawer was taken down.
    struct Closed < Message
      # Which drawer it was.
      getter drawer : Drawer

      def initialize(@drawer : Drawer)
      end
    end

    # Which edge it is against.
    getter edge : Edge

    # How many cells it takes out from that edge: columns for a left or right
    # drawer, rows for a top or bottom one.
    getter size : Int32

    # The key that takes the drawer down, or `nil` for one that has to be
    # closed by the application.
    getter cancel_key : Key?

    # Which z the drawer sits at. Kept because the anchor is rebuilt whenever
    # the edge or the size changes, and the z has to survive that.
    @z : Int32 = Z::DRAWER

    def initialize(edge : Edge = Edge::Left,
                   size : Int32 = 24,
                   modal : Bool = false,
                   backdrop : Bool = false,
                   light_dismiss : Bool = false,
                   z : Int32 = Z::DRAWER,
                   direction : Layout::Direction = Layout::Direction::Column,
                   padding : Layout::Padding = Layout::Padding.all(0),
                   border : Border? = nil,
                   style : Style? = nil,
                   cancel_key : Key? = Key.named(Key::Name::Escape))
      @edge = edge
      @size = size

      super modal: modal, light_dismiss: light_dismiss, backdrop: backdrop, z: z

      @cancel_key = cancel_key
      @direction = direction
      @padding = padding
      @border = border
      @style = style
      @z = z

      apply_edge
      self.keymap = drawer_keymap
    end

    # Puts the drawer against a different edge.
    def edge=(edge : Edge) : Edge
      return edge if edge == @edge

      @edge = edge
      apply_edge
      edge
    end

    # Changes how far the drawer comes out.
    def size=(size : Int32) : Int32
      wanted = Math.max size, 0
      return wanted if wanted == @size

      @size = wanted
      apply_edge
      wanted
    end

    # Takes the drawer down, saying so.
    def close : Nil
      return unless open?

      emit Closed.new self
      super
    end

    # The anchor and the sizing the current edge asks for.
    private def apply_edge : Nil
      element, parent = @edge.attachment
      self.floating = Layout::Floating.on nil, element, parent, z: @z,
        overflow: Layout::Overflow::Clamp

      if @edge.vertical?
        self.width = Layout::Sizing.fixed @size
        self.height = Layout::Sizing.grow
      else
        self.width = Layout::Sizing.grow
        self.height = Layout::Sizing.fixed @size
      end
    end

    # The key that takes the drawer down.
    private def drawer_keymap : Bindings?
      cancel = @cancel_key
      return unless cancel

      Bindings.build do |map|
        map.bind cancel, "close the drawer", ->(_context : Context) { close }
      end
    end
  end
end
