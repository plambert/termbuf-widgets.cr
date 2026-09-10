require "../spec_helper"

# The panes page of `examples/widgets.cr`, in the smallest tree that has the
# same shape: a `VirtualList` in one bordered pane and a `Scrollable` over
# plain labels in the other.
#
# Tab did nothing here, because a scroll panel could not take the keyboard and
# so the ring held only the list, and nothing on the screen said where the
# keyboard was in any case.
Spectator.describe "a list and a scroll panel side by side" do
  alias Panel = TermBuf::Widgets::Panel
  alias Scrollable = TermBuf::Widgets::Scrollable
  alias VirtualList = TermBuf::Widgets::VirtualList
  alias Label = TermBuf::Widgets::Label
  alias Border = TermBuf::Widgets::Border
  alias Style = TermBuf::Style

  # What a focused pane's border is drawn in, which has to differ from the
  # style an unfocused one keeps for the spec to tell them apart.
  ACCENT = Style::DEFAULT.fg TermBuf::Color.rgb(120, 180, 250)

  # How many rows the list holds, and how many labels the scroll panel does.
  ROWS  = 20
  NOTES = 12

  # The two panes, the widgets inside them, and an app drawing the pair.
  #
  # Twenty columns by five rows puts each pane at ten across, which a border
  # leaves eight of, and three rows of content.
  def panes : {Fixtures::TestApp, VirtualList(String), Scrollable, Panel, Panel}
    list = VirtualList.new TermBuf::Widgets::Rows.of(Array.new(ROWS) { |index| "row#{index}" })
    left = Panel.new width: Sizing.grow, height: Sizing.grow,
      border: Border.rounded(title: " rows ")
    left.focused_border_style = ACCENT
    left.add list

    notes = Scrollable.new
    NOTES.times { |index| notes.add Label.new("note#{index}") }
    right = Panel.new width: Sizing.grow, height: Sizing.grow,
      border: Border.plain(title: " notes ")
    right.focused_border_style = ACCENT
    right.add notes

    root = Panel.new direction: Layout::Direction::Row,
      width: Sizing.grow, height: Sizing.grow
    root.add left, right

    app = Fixtures::TestApp.new root, 20, 5
    app.frame

    {app, list, notes, left, right}
  end

  describe "the ring" do
    it "starts on the list" do
      app, list, _, _, _ = panes

      expect(app.focused).to be list
    end

    it "moves to the scroll panel on Tab" do
      app, _, notes, _, _ = panes
      Fixtures.press app, "Tab"

      expect(app.focused).to be notes
    end

    it "comes back to the list on the next one" do
      app, list, _, _, _ = panes
      Fixtures.press app, "Tab"
      Fixtures.press app, "Tab"

      expect(app.focused).to be list
    end

    it "goes back to the scroll panel on Shift+Tab" do
      app, _, notes, _, _ = panes
      Fixtures.press app, "Shift+Tab"

      expect(app.focused).to be notes
    end

    it "holds the two of them and nothing else" do
      app, list, notes, _, _ = panes

      expect(app.focus.top.ring).to eq [list, notes]
    end
  end

  describe "the keys" do
    it "moves the chosen row while the list has the keyboard" do
      app, list, notes, _, _ = panes
      Fixtures.press app, "Down"

      expect(list.selected).to eq 1
      expect(notes.scroll_y).to eq 0
    end

    it "scrolls the panel once the keyboard is on it" do
      app, list, notes, _, _ = panes
      Fixtures.press app, "Tab"
      Fixtures.press app, "Down"

      expect(notes.scroll_y).to eq 1
      expect(list.selected).to eq 0
    end
  end

  describe "what the screen says" do
    # The style of the top left corner of each pane's border.
    def corners(app : Fixtures::TestApp) : {Style, Style}
      app.frame
      {Fixtures.style_at(app.buffer, 0, 0), Fixtures.style_at(app.buffer, 10, 0)}
    end

    it "lights the border of the pane holding the keyboard" do
      app, _, _, _, _ = panes
      lit, dark = corners app

      expect(lit.foreground).to eq ACCENT.foreground
      expect(dark.foreground).to eq Style::DEFAULT.foreground
    end

    it "moves the light with the keyboard" do
      app, _, _, _, _ = panes
      Fixtures.press app, "Tab"
      dark, lit = corners app

      expect(lit.foreground).to eq ACCENT.foreground
      expect(dark.foreground).to eq Style::DEFAULT.foreground
    end

    it "leaves a pane with no focused style alone" do
      app, _, _, left, _ = panes
      left.focused_border_style = nil
      lit, _ = corners app

      expect(lit.foreground).to eq Style::DEFAULT.foreground
    end

    it "reverses the chosen row only while the list has the keyboard" do
      app, list, _, _, _ = panes
      list.on_draw = ->(view : TermBuf::View, _index : Int32, text : String, chosen : Bool, focused : Bool) do
        view.write 0, 0, text, chosen && focused ? Style::DEFAULT.reverse : Style::DEFAULT
        nil
      end

      app.frame
      expect(Fixtures.style_at(app.buffer, 1, 1).attributes.reverse?).to be_true

      Fixtures.press app, "Tab"
      app.frame
      expect(Fixtures.style_at(app.buffer, 1, 1).attributes.reverse?).to be_false
    end
  end
end
