require "./layout/errors"
require "./layout/padding"
require "./layout/sizing"

module TermBuf::Widgets
  # A thing on the screen, and the element the layout engine sizes.
  #
  # There is no separate declaration tree: the object that draws is the object
  # that gets laid out, so nothing has to be kept in step with anything else.
  # Build a tree with `#add`, hand the root to a `Layout::Tree`, and every
  # widget comes back carrying a `#rect` in buffer coordinates.
  #
  # Everything the engine reads is reached through a `layout_property`, which
  # marks the tree dirty when the value changes. Assigning an instance
  # variable directly instead skips that, which is what
  # `Layout::Tree.verify_invalidation` exists to catch.
  #
  # Subclasses supply the parts the engine cannot work out: `#intrinsic_width`
  # for how wide the content wants to be, `#height_for_width` for how tall it
  # turns out at that width, and `#draw` for putting it on the screen.
  abstract class Widget
    # Declares a piece of geometry.
    #
    # Generates a getter and a setter; the setter returns early when the value
    # is unchanged and otherwise assigns and calls `#invalidate_layout`. Every
    # layout input goes through one, because a change nothing is told about is
    # a frame drawn from stale rectangles.
    macro layout_property(declaration)
      @{{ declaration.var }} : {{ declaration.type }} = {{ declaration.value }}

      def {{ declaration.var }} : {{ declaration.type }}
        @{{ declaration.var }}
      end

      def {{ declaration.var }}=(value : {{ declaration.type }}) : {{ declaration.type }}
        return value if @{{ declaration.var }} == value

        @{{ declaration.var }} = value
        invalidate_layout
        value
      end
    end

    # `layout_property` for a flag, whose getter takes a question mark.
    macro layout_property?(declaration)
      @{{ declaration.var }} : {{ declaration.type }} = {{ declaration.value }}

      def {{ declaration.var }}? : {{ declaration.type }}
        @{{ declaration.var }}
      end

      def {{ declaration.var }}=(value : {{ declaration.type }}) : {{ declaration.type }}
        return value if @{{ declaration.var }} == value

        @{{ declaration.var }} = value
        invalidate_layout
        value
      end
    end

    # The widget this one sits inside, or `nil` at the root.
    getter parent : Widget?

    # The widgets laid out inside this one, in order.
    getter children = [] of Widget

    # The tree this widget is the root of. Only a root carries one;
    # `#invalidate_layout` walks up to find it.
    getter tree : Layout::Tree?

    # How wide this widget asks to be.
    layout_property width : Layout::Sizing = Layout::Sizing.fit

    # How tall this widget asks to be.
    layout_property height : Layout::Sizing = Layout::Sizing.fit

    # Which way the children stack.
    layout_property direction : Layout::Direction = Layout::Direction::Column

    # Cells held back inside the widget's own rectangle.
    layout_property padding : Layout::Padding = Layout::Padding.all(0)

    # Cells between one child and the next, along `#direction`.
    layout_property gap : Int32 = 0

    # Where the children sit horizontally in space left over.
    layout_property align_x : Layout::Align = Layout::Align::Start

    # Where the children sit vertically in space left over.
    layout_property align_y : Layout::Align = Layout::Align::Start

    # A box drawn around the widget, taking one cell per side out of the
    # content box. `nil` for none.
    layout_property border : Border? = nil

    # Whether the widget cuts its content at its left and right edges rather
    # than compressing the children to fit. What makes a scroll panel.
    layout_property? clip_x : Bool = false

    # Whether the widget cuts its content at its top and bottom edges rather
    # than compressing the children to fit.
    layout_property? clip_y : Bool = false

    # Columns the content is shifted left by. Only read when `#clip_x?`.
    layout_property scroll_x : Int32 = 0

    # Rows the content is shifted up by. Only read when `#clip_y?`.
    layout_property scroll_y : Int32 = 0

    # Placement for a widget lifted out of its parent's flow, or `nil` for one
    # laid out in it.
    #
    # A float keeps its place in the tree, which is what makes it a child of
    # the thing it belongs to, but its parent's layout takes no space for it:
    # it is laid out against its anchor after the rest of the tree is settled.
    layout_property floating : Layout::Floating? = nil

    # Whether the widget is skipped entirely: no size, no position, and no gap
    # beside it.
    layout_property? hidden : Bool = false

    # What the widget draws in, or `nil` to take the surface's own style.
    property style : Style? = nil

    # The keys this widget answers, or `nil` for one that answers none.
    #
    # Every keymap in the chain from the focused widget up is offered a key at
    # once, innermost first, so a widget's own binding beats the one its parent
    # gives the same key.
    property keymap : Bindings? = nil

    # Where this widget's messages go: set on the root only, by the `Router`.
    # `#emit` walks up to find it, the way `#invalidate_layout` walks up to
    # find the tree.
    property mailbox : Mailbox? = nil

    # Where the engine put this widget, in buffer coordinates.
    getter rect : Rect = Rect.new(0, 0, 0, 0)

    # The smallest this widget and its content can be, as `{width, height}`.
    getter min_size : {Int32, Int32} = {0, 0}

    # :nodoc:
    def rect=(rect : Rect) : Rect
      @rect = rect
    end

    # :nodoc:
    def min_size=(min_size : {Int32, Int32}) : {Int32, Int32}
      @min_size = min_size
    end

    # :nodoc:
    def tree=(tree : Layout::Tree?) : Layout::Tree?
      @tree = tree
    end

    # The smallest width this widget can be laid out at.
    def min_width : Int32
      @min_size[0]
    end

    # The smallest height this widget can be laid out at.
    def min_height : Int32
      @min_size[1]
    end

    # Padding and border together: everything between the widget's own
    # rectangle and the box its children are laid out in.
    def inset : Layout::Padding
      return @padding unless @border

      Layout::Padding.new @padding.top + 1, @padding.right + 1,
        @padding.bottom + 1, @padding.left + 1
    end

    # The box the children are laid out in, in buffer coordinates. Empty when
    # the inset leaves no room.
    def content : Rect
      spacing = inset
      Rect.new @rect.x + spacing.left, @rect.y + spacing.top,
        Math.max(0, @rect.width - spacing.horizontal),
        Math.max(0, @rect.height - spacing.vertical)
    end

    # Whether this widget has no children to lay out.
    def leaf? : Bool
      @children.empty?
    end

    # The children this widget's own layout has room for: everything neither
    # hidden nor floating. A float is laid out against its anchor instead, so
    # its parent reserves nothing for it.
    def visible_children : Array(Widget)
      @children.reject { |child| child.hidden? || child.floating }
    end

    # Whether this widget is lifted out of its parent's flow.
    def floating? : Bool
      !@floating.nil?
    end

    # Whether *root* is this widget or an ancestor of it, which is how a
    # widget still in a tree is told from one taken out of it.
    def under?(root : Widget) : Bool
      node : Widget? = self
      while node
        return true if node.same? root

        node = node.parent
      end

      false
    end

    # The deepest visible widget at (*x*, *y*), or `nil` when the point falls
    # outside this one.
    #
    # Later children win, since they are drawn over their earlier siblings, and
    # a floating child is skipped: a float is placed against the screen rather
    # than inside its parent, so `Layout::Tree#hit` reaches it as a root of its
    # own.
    def at(x : Int32, y : Int32) : Widget?
      return if @hidden || !@rect.contains?(x, y)

      @children.reverse_each do |child|
        next if child.floating

        if found = child.at x, y
          return found
        end
      end

      self
    end

    # Adds *child* at the end and returns it.
    #
    # Raises if *child* already sits in a tree; remove it from its parent
    # first.
    def add(child : Widget) : Widget
      raise Layout::Error.new "#{child.class} already has a parent" if child.parent

      child.parent = self
      @children << child
      invalidate_layout
      child
    end

    # Adds each of *widgets* and returns self, for building a tree in one
    # expression.
    def add(*widgets : Widget) : self
      widgets.each { |widget| add widget }
      self
    end

    # Takes *child* out, returning it, or `nil` when it was not there.
    def remove(child : Widget) : Widget?
      return unless @children.delete child

      child.parent = nil
      invalidate_layout
      child
    end

    # Takes every child out.
    def clear : Nil
      return if @children.empty?

      @children.each &.parent=(nil)
      @children.clear
      invalidate_layout
    end

    # Yields this widget and then every widget under it, parents first.
    #
    # The block is captured rather than yielded because the walk recurses, and
    # a yielding block is inlined at every call site.
    def each_in_tree(&block : Widget ->) : Nil
      block.call self
      # ameba:disable Style/VerboseBlock
      @children.each { |child| child.each_in_tree(&block) }
    end

    # How wide the content wants to be, ignoring everything around it.
    #
    # The engine calls this on leaves only; a widget with children is sized
    # from them. The default is nothing, which is right for a container and
    # wrong for anything that draws.
    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 0, 0
    end

    # How many rows the content takes when it is *width* cells across.
    #
    # Called on leaves after widths are settled, which is where wrapped text
    # gets its height.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      0
    end

    # Draws the widget through *view*, which is already cut to `#rect`.
    def draw(view : View) : Nil
    end

    # Where the terminal's cursor belongs while this widget has focus, or
    # `nil` when it does not want it.
    #
    # In the widget's own content box, which is the box `#draw` is given, so
    # neither a border nor padding has to be counted twice.
    def cursor_position : {Int32, Int32}?
      nil
    end

    # Whether focus can land here.
    def focusable? : Bool
      false
    end

    # What this widget does with an event no binding in the chain claimed.
    #
    # Call `Context#consume` to stop the event here; answering without
    # consuming lets it carry on to the parent, which is what a panel that
    # highlights itself on a key it does not otherwise want should do.
    def handle(event : Event, context : Context) : Nil
    end

    # Sends *message* to whatever contains this widget.
    #
    # It is delivered on the next `App#pump`, starting at this widget's parent,
    # so a widget never sees its own message in the dispatch that emitted it.
    # A widget outside a tree has nowhere to send one, and this does nothing.
    def emit(message : Message) : Nil
      node : Widget? = self
      while node
        if mailbox = node.mailbox
          mailbox.post message, self
          return
        end

        node = node.parent
      end
    end

    # Marks the tree this widget belongs to as needing another layout.
    #
    # Walks up to whichever ancestor carries the tree. A widget not in a tree
    # has nothing to tell, and this does nothing.
    protected def invalidate_layout : Nil
      node : Widget? = self
      while node
        if tree = node.tree
          tree.invalidate
          return
        end
        node = node.parent
      end
    end

    protected setter parent
  end
end
