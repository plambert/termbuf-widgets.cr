require "../../spec_helper"
require "./overlay_harness_spec"

Spectator.describe TermBuf::Widgets::DropdownMenu do
  alias Menu = TermBuf::Widgets::DropdownMenu
  alias Item = TermBuf::Widgets::DropdownMenu::Item
  alias Point = Layout::AttachPoint
  alias Padding = Layout::Padding

  ITEMS = [
    Item.new("Open", hint: "Ctrl+O"),
    Item.new("Save", hint: "Ctrl+S"),
    Item.new("Revert", enabled: false),
    Item.new("Export", submenu: true),
  ]

  # A screen with a small target on it and a menu hanging off it.
  def staged(items : Array(Item) = ITEMS,
             align_y : Layout::Align = Layout::Align::Start,
             max_rows : Int32 = 12,
             rows : Int32 = 14) : {Fixtures::TestApp, Fixtures::Box, Menu}
    root = Fixtures::MessageLog.new width: Sizing.grow, height: Sizing.grow,
      padding: Padding.new(1, 0, 1, 2), align_y: align_y

    target = Fixtures::Box.new
    target.width = Sizing.fixed 6
    target.height = Sizing.fixed 1
    target.focusable = true
    root.add target

    menu = Menu.new target, items, max_rows: max_rows
    app = Fixtures::TestApp.new root, 30, rows
    app.frame
    {app, target, menu}
  end

  # A menu already open, with a frame taken so that hit tests land.
  def opened(**options) : {Fixtures::TestApp, Fixtures::Box, Menu}
    app, target, menu = staged(**options)
    menu.open app
    app.frame
    {app, target, menu}
  end

  describe "moving the highlight" do
    it "starts on the first item" do
      _app, _target, menu = opened

      expect(menu.selected).to eq 0
    end

    it "moves down and up" do
      app, _target, menu = opened
      Fixtures.presses app, "Down"

      expect(menu.selected).to eq 1

      Fixtures.presses app, "Up"

      expect(menu.selected).to eq 0
    end

    it "steps over an item that cannot be chosen" do
      app, _target, menu = opened
      Fixtures.presses app, "Down Down"

      expect(menu.selected).to eq 3
    end

    it "wraps at the end" do
      app, _target, menu = opened
      Fixtures.presses app, "Up"

      expect(menu.selected).to eq 3
    end

    it "starts on the first item that can be chosen" do
      _app, _target, menu = opened items: [Item.new("no", enabled: false), Item.new("yes")]

      expect(menu.selected).to eq 1
    end

    it "goes to the last item that can be chosen" do
      app, _target, menu = opened
      Fixtures.presses app, "End"

      expect(menu.selected).to eq 3
    end
  end

  describe "choosing" do
    it "says which item it was, and closes" do
      app, _target, menu = opened
      Fixtures.presses app, "Down Enter"

      expect(menu.open?).to be_false
      chosen = app.root.as(Fixtures::MessageLog).of Menu::Selected
      expect(chosen.map &.index).to eq [1]
      expect(chosen.map &.item.label).to eq %w[Save]
    end

    it "says nothing for an item that cannot be chosen" do
      app, _target, menu = opened items: [Item.new("no", enabled: false)]
      Fixtures.presses app, "Enter"

      expect(menu.open?).to be_true
      expect(app.root.as(Fixtures::MessageLog).of(Menu::Selected)).to be_empty
    end
  end

  describe "the pointer" do
    it "highlights whatever it is moved over" do
      app, _target, menu = opened
      box = menu.list.content
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Motion, box.x, box.y + 1,
        TermBuf::Input::Mouse::Button::None

      expect(menu.selected).to eq 1
    end

    it "chooses whatever is pressed" do
      app, _target, menu = opened
      box = menu.list.content
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, box.x, box.y + 1

      expect(menu.open?).to be_false
      expect(app.root.as(Fixtures::MessageLog).of(Menu::Selected).map &.index).to eq [1]
    end

    it "refuses an item that cannot be chosen" do
      app, _target, menu = opened
      box = menu.list.content
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, box.x, box.y + 2

      expect(menu.open?).to be_true
      expect(menu.selected).to eq 3
    end

    it "goes away on a press outside it" do
      app, _target, menu = opened
      Fixtures.mouse app, TermBuf::Input::Mouse::Action::Press, 29, 13

      expect(menu.open?).to be_false
    end
  end

  describe "where it lands" do
    it "is as wide as its widest line" do
      _app, _target, menu = opened

      widest = "Open".size + Menu::List::GAP + "Ctrl+O".size
      expect(menu.rect.width).to eq widest + 2
      expect(menu.rect.height).to eq ITEMS.size + 2
    end

    it "draws the labels and the hints" do
      app, _target, _menu = opened
      lines = app.lines

      expect(lines.any?(&.includes?("Open"))).to be_true
      expect(lines.any?(&.includes?("Ctrl+S"))).to be_true
      expect(lines.any?(&.includes?(Menu::List::SUBMENU))).to be_true
    end

    it "flips above the target when there is no room below it" do
      _app, target, menu = opened align_y: Layout::Align::End

      expect(menu.rect.bottom).to eq target.rect.y - 1
    end

    it "shows no more rows than it was told to, and scrolls the rest" do
      many = Array.new(20) { |index| Item.new "item #{index}" }
      app, _target, menu = opened items: many, max_rows: 4

      expect(menu.list.rect.height).to eq 4
      Fixtures.presses app, "End"

      expect(menu.selected).to eq 19
      expect(menu.list.visible_range.includes?(19)).to be_true
    end
  end
end
