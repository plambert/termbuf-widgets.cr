require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::HelpOverlay do
  alias Help = TermBuf::Widgets::HelpOverlay
  alias Context = TermBuf::Widgets::Context
  alias Bindings = TermBuf::Widgets::Bindings

  # A keymap binding *keys*, each doing nothing.
  def keymap_of(keys : Enumerable(String), description : String) : Bindings
    map = Bindings.new
    keys.each do |key|
      map.bind Key.parse(key), description, ->(_context : Context) { }
    end
    map
  end

  # A screen whose focusable widget binds two keys of its own.
  def staged(max_rows : Int32 = 14) : {Fixtures::Ground, Help}
    ground = Fixtures::Ground.new
    ground.under.keymap = keymap_of({"Ctrl+S", "Ctrl+O"}, "do the thing"
    )
    {ground, Help.new max_rows: max_rows}
  end

  describe "what it lists" do
    it "lists the bindings of the chain the keyboard is in" do
      ground, help = staged
      help.open ground.app

      expect(help.rows.reject(&.header).map &.keys).to eq [
        "Ctrl+S", "Ctrl+O", "Tab", "Shift+Tab",
      ]
    end

    it "groups them by where they came from" do
      ground, help = staged
      help.open ground.app

      expect(help.rows.select(&.header).map &.keys).to eq ["Box", Help::SCOPE]
      expect(help.rows.first.header).to be_true
    end

    it "carries the description each binding was given" do
      ground, help = staged
      help.open ground.app

      expect(help.rows.reject(&.header).first.description).to eq "do the thing"
    end

    it "reads them again every time it opens" do
      ground, help = staged
      help.open ground.app
      help.close
      ground.under.keymap = keymap_of({"Ctrl+Q"}, "leave")
      help.open ground.app

      expect(help.rows.reject(&.header).map &.keys).to eq %w[Ctrl+Q Tab Shift+Tab]
    end

    it "leaves the highlight off a heading" do
      ground, help = staged
      help.open ground.app

      expect(help.list.selected).to eq 1
    end

    it "draws the keys and what they do" do
      ground, help = staged
      help.open ground.app
      lines = ground.lines

      expect(lines.any?(&.includes?("Ctrl+S"))).to be_true
      expect(lines.any?(&.includes?("do the thing"))).to be_true
      expect(lines.any?(&.includes?("Box"))).to be_true
    end
  end

  describe "a list too long to show" do
    it "shows no more rows than it was told to, and scrolls the rest" do
      ground = Fixtures::Ground.new
      # Not every control letter is a key of its own: a terminal sends the
      # same byte for `Ctrl+I` as for `Tab`, and the keymap folds them onto
      # one, so binding both would be a conflict.
      letters = ('a'..'z').reject(&.in?('h', 'i', 'm')).first 20
      ground.under.keymap = keymap_of(letters.map { |letter| "Ctrl+#{letter}" }, "one of many")
      help = Help.new max_rows: 5
      help.open ground.app
      ground.app.frame

      expect(help.list.rect.height).to eq 5
      expect(help.rows.size).to eq 24

      ground.press "End"

      expect(help.list.selected).to eq 23
      expect(help.list.visible_range.includes?(23)).to be_true
    end
  end

  describe "the keys that put it up" do
    it "opens on F1 and on a question mark" do
      ground = Fixtures::Ground.new
      help = Help.install ground.app
      ground.press "F1"

      expect(help.open?).to be_true

      ground.press "Escape"

      expect(help.open?).to be_false

      ground.press "?"

      expect(help.open?).to be_true
    end

    it "leaves the bindings that were already there" do
      ground = Fixtures::Ground.new
      Help.install ground.app

      expect(ground.app.keymap.bindings.map &.to_s).to eq [
        "Tab", "Shift+Tab", "F1", "?",
      ]
      expect(ground.app.focus.scopes.first.keymap).to be ground.app.keymap
    end

    it "takes whatever keys it is given instead" do
      ground = Fixtures::Ground.new
      help = Help.install ground.app, keys: {"Ctrl+G"}
      ground.press "Ctrl+G"

      expect(help.open?).to be_true
    end
  end
end
