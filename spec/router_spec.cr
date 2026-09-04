require "./spec_helper"

Spectator.describe TermBuf::Widgets::Router do
  alias Box = Fixtures::Box
  alias Focus = TermBuf::Widgets::Focus
  alias Router = TermBuf::Widgets::Router
  alias Context = TermBuf::Widgets::Context
  alias Bindings = TermBuf::Widgets::Bindings

  def target(width : Int32 = 2) : Box
    made = Box.sized width, 1
    made.focusable = true
    made
  end

  def key(character : Char) : TermBuf::Events::Key
    TermBuf::Events::Key.new TermBuf::Key.character(character), Bytes.empty
  end

  def keys(text : String) : Array(TermBuf::Events::Key)
    TermBuf::Key.parse(text).map { |one| TermBuf::Events::Key.new one, Bytes.empty }
  end

  # A laid-out tree with a focus stack and a router over it.
  def wired(root : Box) : {Router, Focus::Stack}
    tree = TermBuf::Widgets::Layout::Tree.new root, Rect.full(20, 6)
    tree.layout
    focus = Focus::Stack.new root
    {Router.new(tree, focus), focus}
  end

  # A root holding a panel holding the focused leaf.
  def nested : {Router, Focus::Stack, Box, Box, Box}
    root = Box.new
    panel = Box.new
    leaf = target
    panel.add leaf
    root.add panel

    router, focus = wired root
    {router, focus, root, panel, leaf}
  end

  describe "where an event goes" do
    it "starts at the focused widget and walks up through its parents" do
      router, _, root, panel, leaf = nested
      router.dispatch key('a')

      expect(leaf.seen.size).to eq 1
      expect(panel.seen.size).to eq 1
      expect(root.seen.size).to eq 1
    end

    it "stops where something claims it" do
      router, _, root, panel, leaf = nested
      panel.on_handle = ->(_event : TermBuf::Event, context : Context) { context.consume }

      expect(router.dispatch(key('a'))).to be_true
      expect(leaf.seen.size).to eq 1
      expect(panel.seen.size).to eq 1
      expect(root.seen).to be_empty
    end

    it "carries on past a widget that reacted without claiming it" do
      router, _, root, _, leaf = nested
      reacted = 0
      leaf.on_handle = ->(_event : TermBuf::Event, _context : Context) { reacted += 1; nil }

      expect(router.dispatch(key('a'))).to be_false
      expect(reacted).to eq 1
      expect(root.seen.size).to eq 1
    end

    it "answers false when nothing wanted it" do
      router, _, _, _, _ = nested
      expect(router.dispatch(key('a'))).to be_false
    end

    it "goes nowhere when nothing has the keyboard" do
      root = Box.new
      root.add Box.sized(2, 1)
      router, _ = wired root

      expect(router.dispatch(key('a'))).to be_false
      expect(root.seen).to be_empty
    end

    it "stops at the top scope's root" do
      root = Box.new
      dialog = Box.new
      leaf = target
      dialog.add leaf
      root.add dialog

      router, focus = wired root
      focus.push dialog
      router.dispatch key('a')

      expect(leaf.seen.size).to eq 1
      expect(dialog.seen.size).to eq 1
      expect(root.seen).to be_empty
    end

    it "aims a positioned event at whatever is under the point" do
      root = Box.new
      root.direction = TermBuf::Widgets::Layout::Direction::Row
      left = target 4
      right = target 4
      root.add left, right

      router, _ = wired root
      router.dispatch Fixtures::Click.new(5, 0)

      expect(right.seen.size).to eq 1
      expect(left.seen).to be_empty
      expect(root.seen.size).to eq 1
    end
  end

  describe "bindings" do
    it "fires before the widget is asked" do
      router, _, _, _, leaf = nested
      fired = 0
      leaf.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('a'), "do it", ->(_context : Context) { fired += 1; nil }
      end

      expect(router.dispatch(key('a'))).to be_true
      expect(fired).to eq 1
      expect(leaf.seen).to be_empty
    end

    it "lets a widget's own binding beat the one its parent gives the key" do
      router, _, _, panel, leaf = nested
      claimed = [] of String
      leaf.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('a'), "inner", ->(_context : Context) { claimed << "inner"; nil }
      end
      panel.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('a'), "outer", ->(_context : Context) { claimed << "outer"; nil }
      end

      router.dispatch key('a')
      expect(claimed).to eq ["inner"]
    end

    it "falls back to the parent for a key the child does not bind" do
      router, _, _, panel, leaf = nested
      claimed = [] of String
      leaf.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('a'), "inner", ->(_context : Context) { claimed << "inner"; nil }
      end
      panel.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('b'), "outer", ->(_context : Context) { claimed << "outer"; nil }
      end

      router.dispatch key('b')
      expect(claimed).to eq ["outer"]
    end

    it "answers the scope's keymap after every widget has declined" do
      root = Box.new
      leaf = target
      root.add leaf
      tree = TermBuf::Widgets::Layout::Tree.new root, Rect.full(20, 6)
      tree.layout

      fired = 0
      scoped = Bindings.build do |map|
        map.bind TermBuf::Key.character('q'), "quit", ->(_context : Context) { fired += 1; nil }
      end
      router = Router.new tree, Focus::Stack.new(root, scoped)

      expect(router.dispatch(key('q'))).to be_true
      expect(fired).to eq 1
    end

    it "holds the first key of a sequence and fires on the last" do
      router, _, _, _, leaf = nested
      fired = 0
      leaf.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.parse("Ctrl+x Ctrl+s"), "save", ->(_context : Context) { fired += 1; nil }
      end

      first, second = keys "Ctrl+x Ctrl+s"
      expect(router.dispatch(first)).to be_true
      expect(fired).to eq 0
      expect(leaf.seen).to be_empty

      expect(router.dispatch(second)).to be_true
      expect(fired).to eq 1
    end

    it "forgets half a sequence when the keyboard moves" do
      root = Box.new
      first = target
      second = target
      root.add first, second
      router, focus = wired root

      fired = 0
      first.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.parse("Ctrl+x Ctrl+s"), "save", ->(_context : Context) { fired += 1; nil }
      end

      router.dispatch keys("Ctrl+x").first
      focus.focus second
      router.dispatch keys("Ctrl+s").first

      expect(fired).to eq 0
      expect(router.matcher.pending).to be_empty
    end
  end

  describe "#active_bindings" do
    it "lists the chain innermost first, each with where it came from" do
      root = Box.new
      panel = Box.new
      leaf = target
      panel.add leaf
      root.add panel

      tree = TermBuf::Widgets::Layout::Tree.new root, Rect.full(20, 6)
      tree.layout
      scoped = Bindings.build do |map|
        map.bind TermBuf::Key.character('q'), "quit", ->(_context : Context) { nil }
      end
      router = Router.new tree, Focus::Stack.new(root, scoped)

      leaf.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('a'), "accept", ->(_context : Context) { nil }
      end
      panel.keymap = Bindings.build do |map|
        map.bind TermBuf::Key.character('c'), "cancel", ->(_context : Context) { nil }
      end

      listed = router.active_bindings
      expect(listed.map(&.[0].description)).to eq ["accept", "cancel", "quit"]
      expect(listed.map { |pair| pair[1] }).to eq [leaf, panel, nil]
    end
  end

  describe "messages" do
    it "does not reach the widget that sent it, nor in the dispatch that sent it" do
      router, _, root, panel, leaf = nested
      leaf.on_handle = ->(event : TermBuf::Event, _context : Context) do
        leaf.emit Fixtures::Said.new("hello") if event.is_a? TermBuf::Events::Key
        nil
      end

      router.dispatch key('a')
      expect(leaf.seen.size).to eq 1
      expect(panel.seen.size).to eq 1
      expect(root.seen.size).to eq 1
      expect(router.pending.size).to eq 1
    end

    it "arrives on the next drain, from the emitter's parent upward" do
      router, _, root, panel, leaf = nested
      leaf.emit Fixtures::Said.new("hello")

      expect(router.drain).to eq 1
      expect(panel.seen.map(&.class)).to eq [Fixtures::Said]
      expect(root.seen.map(&.class)).to eq [Fixtures::Said]
      expect(leaf.seen).to be_empty
    end

    it "leaves a message emitted while draining for the drain after" do
      router, _, _, panel, leaf = nested
      panel.on_handle = ->(event : TermBuf::Event, _context : Context) do
        panel.emit Fixtures::Said.new("again") if event.is_a? Fixtures::Said
        nil
      end

      leaf.emit Fixtures::Said.new("hello")
      expect(router.drain).to eq 1
      expect(router.pending.size).to eq 1
      expect(router.drain).to eq 1
      expect(router.pending).to be_empty
    end

    it "goes nowhere for a widget outside a tree" do
      loose = Box.new
      expect { loose.emit Fixtures::Said.new("nobody") }.not_to raise_error
    end
  end
end
