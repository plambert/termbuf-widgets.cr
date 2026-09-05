require "../../message"
require "../virtual_list"
require "./nodes"

module TermBuf::Widgets
  # One line of a `Tree`: a node, how deep it sits, and what it looked like
  # when the tree was last flattened.
  record TreeRow(T), value : T, depth : Int32, expanded : Bool, leaf : Bool do
    # Whether this node is open, which only a node with children can be.
    def expanded? : Bool
      @expanded
    end

    # Whether it has nothing under it.
    def leaf? : Bool
      @leaf
    end
  end

  # Nodes with nodes under them, flattened into the rows of a virtual list.
  #
  #     tree = Tree.new Nodes.from(roots,
  #       children: ->(path : Path) { entries_of path },
  #       label: ->(path : Path) { path.basename },
  #       leaf: ->(path : Path) { !Dir.exists? path })
  #
  # What is on screen is a `VirtualList`, which the tree holds as its one
  # child: the open nodes are walked into one flat array and the list is given
  # a `Rows` over it, so only the rows in the window are ever drawn. A closed
  # subtree is not in the array at all, so a tree over a million files costs
  # what the part of it somebody has opened costs.
  #
  # The list takes the keyboard and the tree sits above it, which is what puts
  # the list's own movement keys and the tree's `Right`, `Left` and `Enter` in
  # one chain without either having to know about the other. A `Scrollbar`
  # attaches to `#list`, which is the `Scrolls`; the tree itself is not one,
  # because a generic widget that both includes `Scrolls` and hands a closure
  # over itself to one of its children is a widget the compiler cannot work
  # the instance variables of out.
  #
  # Children are asked for once, the first time a node is opened, and kept. A
  # source that loads them from somewhere slow is therefore a source that
  # loads each node once; `#refresh` throws the answers away when the
  # underlying data has moved on.
  #
  # ### Keys
  #
  # `Right` opens a closed node and steps into an open one, `Left` closes an
  # open node and steps out to the parent of a closed one, and `Enter` opens or
  # closes a node and emits `Activated` for a leaf.
  #
  # ### Glyphs
  #
  # `#glyphs` is a set of three characters — open, closed, leaf. Left `nil`,
  # which is the default, the set is chosen from the tree's
  # `TermBuf::Unicode::WidthPolicy` at every draw: the triangles when every one
  # of them is a single cell under that policy, and the ASCII set when one is
  # not. A terminal that draws a triangle two cells wide would indent every
  # row under it by a cell too many.
  class Tree(T) < Widget
    # A leaf was activated.
    struct Activated(U) < Message
      # Which node it was.
      getter node : U

      def initialize(@node : U)
      end
    end

    # The three characters a tree is drawn with.
    record Glyphs, open : Char, closed : Char, leaf : Char do
      # Triangles, which is what a tree looks like on a terminal that can draw
      # one.
      UNICODE = new '▼', '▶', ' '

      # The fallback, for a policy that would draw the triangles wide.
      ASCII = new '-', '+', ' '

      # Whether every character here is exactly one cell under *policy*.
      def single_width?(policy : Unicode::WidthPolicy) : Bool
        each.all? { |char| Unicode.string_width(char.to_s, policy) == 1 }
      end

      # The three, open first.
      def each : Iterator(Char)
        {@open, @closed, @leaf}.each
      end

      # The set to use under *policy* when nothing named one.
      def self.for(policy : Unicode::WidthPolicy) : Glyphs
        UNICODE.single_width?(policy) ? UNICODE : ASCII
      end
    end

    # Where the nodes come from.
    getter source : Nodes(T)

    # The window the rows are shown through, which is this tree's one child.
    getter list : VirtualList(T)

    # Cells of indentation per level.
    property indent : Int32 = 2

    # The characters to draw with, or `nil` to choose from the width policy.
    property glyphs : Glyphs? = nil

    # What marks a label cut short at the right edge.
    property ellipsis : String = "…"

    # What the chosen row is drawn in.
    property selected_style : Style = Style::DEFAULT.reverse

    # What draws one row, or `nil` for the default, which writes the indent,
    # the expander and the label.
    property on_draw : Proc(View, Int32, T, Bool, Nil)? = nil

    # The nodes that are open.
    @expanded = Set(T).new

    # What each node answered when it was first opened.
    @loaded = {} of T => Array(T)

    # The rows as they last came out. Filled in place rather than replaced, so
    # the `Rows` the list was given can hold the array itself and never this
    # tree: a closure over `self` here is a closure the compiler has to type
    # while it is still working out what this tree is.
    @flat = [] of TreeRow(T)

    def initialize(@source : Nodes(T),
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow(min: 1),
                   indent : Int32 = 2,
                   glyphs : Glyphs? = nil,
                   style : Style? = nil)
      @indent = indent
      @glyphs = glyphs
      @width = width
      @height = height
      @style = style

      flat = @flat
      rebuild

      @list = VirtualList(T).new Rows(T).from(-> { flat.size },
        ->(index : Int32) { flat[index].value })
      @list.on_draw = ->(view : View, index : Int32, node : T, chosen : Bool) do
        paint view, index, node, chosen
      end

      add @list
      self.keymap = walking
    end

    # ---------------------------------------------------------- flattening

    # Every row that is showing, top first, worked out whenever something opens
    # or closes and kept between times.
    def flatten : Array(TreeRow(T))
      @flat
    end

    # Walks the open nodes into `#flatten` again.
    private def rebuild : Nil
      @flat.clear
      @source.roots.each { |node| gather node, 0, @flat }
    end

    private def gather(node : T, depth : Int32, into : Array(TreeRow(T))) : Nil
      leaf = @source.leaf? node
      open = !leaf && @expanded.includes?(node)
      into << TreeRow(T).new(node, depth, open, leaf)
      return unless open

      children_of(node).each { |child| gather child, depth + 1, into }
    end

    # What hangs under *node*, asked of the source once and kept.
    def children_of(node : T) : Array(T)
      @loaded[node] ||= @source.children node
    end

    # Throws away everything asked of the source, so a tree whose data has
    # moved on shows what is there now. What is open stays open.
    def refresh : Nil
      @loaded.clear
      reflatten
    end

    # Where *node* is showing, or `nil` when it is not.
    def row_of(node : T) : Int32?
      @flat.index { |row| row.value == node }
    end

    # Whether *node* is open.
    def expanded?(node : T) : Bool
      @expanded.includes? node
    end

    # ------------------------------------------------------- the selection

    # Which row is chosen, from zero.
    def selected : Int32
      @list.selected
    end

    # Chooses row *index*, held inside the rows there are, and brings it into
    # view.
    def select(index : Int32) : Nil
      @list.select index
    end

    # The row the selection is on, or `nil` when there are none.
    def current : TreeRow(T)?
      @flat[@list.selected]?
    end

    # The node the selection is on, or `nil` when there are no rows.
    def node : T?
      current.try &.value
    end

    # Where the parent of the row at *index* is showing, or `nil` for a row at
    # the top.
    def parent_of(index : Int32) : Int32?
      flat = @flat
      row = flat[index]?
      return unless row && row.depth > 0

      cursor = index - 1
      while cursor >= 0
        return cursor if flat[cursor].depth < row.depth

        cursor -= 1
      end

      nil
    end

    # ------------------------------------------------------- opening rows

    # Opens *node*, asking the source for its children the first time.
    def expand(node : T) : Nil
      return if @source.leaf? node
      return if @expanded.includes? node

      @expanded << node
      children_of node
      reflatten
    end

    # Closes *node*. A selection inside it comes out to sit on it.
    def collapse(node : T) : Nil
      return unless @expanded.includes? node

      keeping = inside?(node) ? node : node_selected
      @expanded.delete node
      reflatten keeping
    end

    # Closes *node* if it is open and opens it if it is not.
    def toggle(node : T) : Nil
      expanded?(node) ? collapse(node) : expand(node)
    end

    # Opens every node there is, which means asking the source for the
    # children of all of them.
    def expand_all : Nil
      @source.roots.each { |node| open_deep node }
      reflatten
    end

    # Closes everything.
    def collapse_all : Nil
      return if @expanded.empty?

      keeping = node_selected
      @expanded.clear
      reflatten keeping
    end

    private def open_deep(node : T) : Nil
      return if @source.leaf? node

      @expanded << node
      children_of(node).each { |child| open_deep child }
    end

    # The node the selection is on before a reflattening, so it can be put
    # back on it afterwards.
    private def node_selected : T?
      @flat[@list.selected]?.try &.value
    end

    # Whether the selection is on something under *node*.
    private def inside?(node : T) : Bool
      flat = @flat
      at = flat.index { |row| row.value == node }
      return false unless at

      depth = flat[at].depth
      cursor = at + 1

      while cursor < flat.size && flat[cursor].depth > depth
        return true if cursor == @list.selected

        cursor += 1
      end

      false
    end

    # Works the rows out again, putting the selection back on *keeping* when
    # that node is still showing and holding it inside the rows when it is
    # not.
    private def reflatten(keeping : T? = nil) : Nil
      wanted = keeping.nil? ? node_selected : keeping
      rebuild

      found = wanted.nil? ? nil : @flat.index { |row| row.value == wanted }
      @list.select(found || Math.min(@list.selected, Math.max(@flat.size - 1, 0)))
    end

    # ------------------------------------------------------------ the window

    # Rows there are, and cells across, as `#list` answers it.
    def content_size : {Int32, Int32}
      @list.content_size
    end

    # Rows that fit.
    def viewport_size : {Int32, Int32}
      @list.viewport_size
    end

    # The first row showing.
    def scroll : Int32
      @list.scroll
    end

    # Moves the window, stopping at either end.
    def scroll_by(dy : Int32) : Nil
      @list.scroll_by 0, dy
    end

    # ------------------------------------------------------------- events

    # Opens the row the selection is on, or steps into it when it is already
    # open.
    def open_row : Nil
      row = current
      return unless row
      return if row.leaf?

      row.expanded? ? @list.select(@list.selected + 1) : expand(row.value)
    end

    # Closes the row the selection is on, or steps out to its parent when it
    # is already closed.
    def close_row : Nil
      row = current
      return unless row

      return collapse row.value if row.expanded?

      parent = parent_of @list.selected
      @list.select parent if parent
    end

    # Opens or closes the row the selection is on, and emits `Activated` for a
    # leaf.
    def use_row : Nil
      row = current
      return unless row

      return emit Activated(T).new(row.value) if row.leaf?

      toggle row.value
    end

    # The keys a tree answers on top of the list's own.
    private def walking : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Right"), "open this node", ->(_context : Context) { open_row }
        map.bind Key.parse("Left"), "close this node", ->(_context : Context) { close_row }
        map.bind Key.parse("Enter"), "use this node", ->(_context : Context) { use_row }
      end
    end

    # ------------------------------------------------------------ drawing

    # The characters this tree draws with under *policy*.
    def glyphs_for(policy : Unicode::WidthPolicy) : Glyphs
      @glyphs || Glyphs.for(policy)
    end

    # What one row reads as: its indent, its expander, and its label.
    def text_of(row : TreeRow(T), policy : Unicode::WidthPolicy) : String
      set = glyphs_for policy
      marker = row.leaf? ? set.leaf : (row.expanded? ? set.open : set.closed)

      "#{" " * (row.depth * @indent)}#{marker} #{@source.label(row.value)}"
    end

    # Draws one row of the list, which is what the list was handed when it was
    # built.
    private def paint(view : View, index : Int32, node : T, chosen : Bool) : Nil
      hook = @on_draw
      return hook.call view, index, node, chosen if hook

      row = @flat[index]?
      return unless row

      text = Unicode.ellipsize text_of(row, view.policy), view.width, @ellipsis, view.policy
      view.write 0, 0, text, chosen ? @selected_style : Style::DEFAULT
    end
  end
end
