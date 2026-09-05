require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Tree do
  alias Tree = TermBuf::Widgets::Tree
  alias Nodes = TermBuf::Widgets::Nodes
  alias Glyphs = TermBuf::Widgets::Tree::Glyphs

  # A source that writes down every question, so a spec can say what the tree
  # asked for rather than how long it took.
  class Counting < Nodes(String)
    # Every node whose children were asked for, in order.
    getter asked = [] of String

    # Every node that was written out, in order.
    getter labelled = [] of String

    def initialize(@under : Hash(String, Array(String)), @tops : Array(String))
    end

    def roots : Array(String)
      @tops
    end

    def children(node : String) : Array(String)
      @asked << node
      @under[node]? || [] of String
    end

    def leaf?(node : String) : Bool
      (@under[node]? || [] of String).empty?
    end

    def label(node : String) : String
      @labelled << node
      node
    end
  end

  # a holds a1 and a2, a1 holds a1x, and b holds nothing.
  def source : Counting
    Counting.new({"a" => %w[a1 a2], "a1" => %w[a1x]}, %w[a b])
  end

  def tree(from : Counting = source) : Tree(String)
    Tree.new from, glyphs: Glyphs::ASCII
  end

  def settle(made : Tree(String), columns : Int32 = 14,
             rows : Int32 = 6) : Tree(String)
    Layout::Tree.new(made, Rect.full(columns, rows)).layout
    made
  end

  # A tree under an app, with a box above it writing down every message.
  def wired(made : Tree(String), columns : Int32 = 14,
            rows : Int32 = 6) : {Fixtures::TestApp, Array(TermBuf::Widgets::Message)}
    root = Fixtures::Box.new
    root.width = Sizing.grow
    root.height = Sizing.grow
    seen = [] of TermBuf::Widgets::Message
    root.on_handle = ->(event : TermBuf::Event, _context : TermBuf::Widgets::Context) do
      seen << event if event.is_a? TermBuf::Widgets::Message
      nil
    end
    root.add made

    app = Fixtures::TestApp.new root, columns, rows
    app.frame
    # The list is the widget focus lands on; the tree sits above it in the
    # chain and answers the keys the list does not.
    app.focus.focus made.list

    {app, seen}
  end

  describe "flattening" do
    it "shows the roots and nothing under them" do
      expect(tree.flatten.map(&.value)).to eq %w[a b]
    end

    it "shows what an open node holds, in place" do
      made = tree
      made.expand "a"

      expect(made.flatten.map(&.value)).to eq %w[a a1 a2 b]
    end

    it "counts how deep each row sits" do
      made = tree
      made.expand "a"
      made.expand "a1"

      expect(made.flatten.map(&.depth)).to eq [0, 1, 2, 1, 0]
    end

    it "takes a closed subtree out again" do
      made = tree
      made.expand "a"
      made.expand "a1"
      made.collapse "a"

      expect(made.flatten.map(&.value)).to eq %w[a b]
    end

    it "opens every node there is" do
      made = tree
      made.expand_all

      expect(made.flatten.map(&.value)).to eq %w[a a1 a1x a2 b]
    end

    it "closes every node there is" do
      made = tree
      made.expand_all
      made.collapse_all

      expect(made.flatten.map(&.value)).to eq %w[a b]
    end

    it "says which nodes are leaves" do
      made = tree
      made.expand "a"

      expect(made.flatten.map(&.leaf?)).to eq [false, false, true, true]
    end

    it "refuses to open a leaf" do
      made = tree
      made.expand "b"

      expect(made.expanded? "b").to be_false
      expect(made.flatten.size).to eq 2
    end
  end

  describe "asking the source" do
    it "asks for children only when a node is opened" do
      from = source
      made = tree from
      made.flatten

      expect(from.asked).to be_empty

      made.expand "a"
      expect(from.asked).to eq %w[a]
    end

    it "asks once and keeps the answer" do
      from = source
      made = tree from
      made.expand "a"
      made.collapse "a"
      made.expand "a"
      made.flatten

      expect(from.asked).to eq %w[a]
    end

    it "asks again after it is told the data moved on" do
      from = source
      made = tree from
      made.expand "a"
      made.refresh
      made.flatten

      expect(from.asked).to eq %w[a a]
    end

    it "writes out only the rows that are showing" do
      wide = Hash(String, Array(String)).new
      wide["root"] = Array.new(500) { |index| "leaf#{index}" }
      from = Counting.new wide, %w[root]
      made = tree from
      made.expand "root"
      Fixtures.render made, 14, 4

      expect(from.labelled.size).to eq 4
    end
  end

  describe "what it draws" do
    it "puts an expander in front of a node and indents what is under it" do
      made = tree
      made.expand "a"

      expect(Fixtures.render(made, 14, 5)).to eq ["- a", "  + a1", "    a2", "  b", ""]
    end

    it "marks a closed node differently from an open one" do
      expect(Fixtures.render(tree, 14, 3)).to eq ["+ a", "  b", ""]
    end

    it "indents by however many cells it was told to" do
      made = tree
      made.indent = 4
      made.expand "a"

      expect(Fixtures.render(made, 14, 2)).to eq ["- a", "    + a1"]
    end

    it "cuts a row too wide for the window and says so" do
      deep = Counting.new({"root" => ["a name nobody sized for"]}, %w[root])
      made = tree deep
      made.expand "root"

      expect(Fixtures.render(made, 12, 2)).to eq ["- root", "    a name …"]
    end

    it "reverses the chosen row" do
      made = tree
      buffer = Fixtures.painted made, 14, 3

      expect(Fixtures.style_at(buffer, 0, 0).attributes.reverse?).to be_true
      expect(Fixtures.style_at(buffer, 0, 1).attributes.reverse?).to be_false
    end

    it "takes the triangles when the terminal draws them one cell wide" do
      expect(Glyphs.for(TermBuf::Unicode::WidthPolicy::DEFAULT)).to eq Glyphs::UNICODE
    end

    it "falls back to ASCII when it would draw them wide" do
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Glyphs.for(cjk)).to eq Glyphs::ASCII
    end
  end

  describe "the keys" do
    it "opens a closed node with Right" do
      made = tree
      app, _ = wired made
      Fixtures.press app, "Right"

      expect(made.expanded? "a").to be_true
      expect(made.selected).to eq 0
    end

    it "steps into an open node with Right" do
      made = tree
      app, _ = wired made
      Fixtures.press app, "Right Right"

      expect(made.selected).to eq 1
      expect(made.node).to eq "a1"
    end

    it "does nothing on Right at a leaf" do
      made = tree
      app, _ = wired made
      Fixtures.press app, "Down Right"

      expect(made.selected).to eq 1
      expect(made.node).to eq "b"
    end

    it "closes an open node with Left" do
      made = tree
      app, _ = wired made
      Fixtures.press app, "Right Left"

      expect(made.expanded? "a").to be_false
      expect(made.selected).to eq 0
    end

    it "steps out to the parent with Left on a closed node" do
      made = tree
      app, _ = wired made
      made.expand "a"
      made.select 2

      Fixtures.press app, "Left"
      expect(made.node).to eq "a"
      expect(made.selected).to eq 0
    end

    it "opens and closes a node with Enter" do
      made = tree
      app, _ = wired made

      Fixtures.press app, "Enter"
      expect(made.expanded? "a").to be_true

      Fixtures.press app, "Enter"
      expect(made.expanded? "a").to be_false
    end

    it "says a leaf was used on Enter" do
      made = tree
      app, seen = wired made
      Fixtures.press app, "Down Enter"
      app.pump

      used = seen.select Tree::Activated(String)
      expect(used.size).to eq 1
      expect(used.first.node).to eq "b"
    end

    it "moves the selection with the list's own keys" do
      made = tree
      app, _ = wired made
      made.expand_all

      Fixtures.press app, "End"
      expect(made.node).to eq "b"

      Fixtures.press app, "Home"
      expect(made.node).to eq "a"
    end
  end

  describe "the selection" do
    it "comes out of a subtree that was closed under it" do
      made = settle tree
      made.expand "a"
      made.select 2
      made.collapse "a"

      expect(made.selected).to eq 0
      expect(made.node).to eq "a"
    end

    it "stays on the node it was on when something above it opens" do
      made = settle tree
      made.select 1
      made.expand "a"

      expect(made.node).to eq "b"
      expect(made.selected).to eq 3
    end

    it "answers where a node is showing" do
      made = tree
      made.expand "a"

      expect(made.row_of "a2").to eq 2
      expect(made.row_of "a1x").to be_nil
    end
  end

  describe "with a scrollbar beside it" do
    it "shows how far down the rows the list has got" do
      deep = Counting.new({"root" => Array.new(16) { |index| "leaf#{index}" }}, %w[root])
      made = tree deep
      made.expand "root"

      root = TermBuf::Widgets::Panel.new direction: Layout::Direction::Row,
        width: Sizing.grow, height: Sizing.grow
      bar = TermBuf::Widgets::Scrollbar.new made.list
      root.add made, bar

      Layout::Tree.new(root, Rect.full(12, 4)).layout
      expect(made.content_size).to eq({11, 17})
      expect(bar.thumb_start).to eq 0

      made.select 16
      expect(bar.thumb_start).to be > 0
    end
  end
end
