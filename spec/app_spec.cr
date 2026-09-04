require "./spec_helper"

Spectator.describe TermBuf::Widgets::App do
  alias Box = Fixtures::Box
  alias Label = TermBuf::Widgets::Label

  describe "#frame" do
    it "lays out, draws, and answers where the cursor goes" do
      root = Box.new
      root.padding = Layout::Padding.new 1, 0, 0, 2
      field = Box.sized 4, 1
      field.cursor = {2, 0}
      root.add field

      app = Fixtures::TestApp.new root, 10, 3
      app.focused = field

      expect(app.frame).to eq({4, 1})
      expect(app.cursor).to eq({4, 1})
    end

    it "hides the cursor when nothing is focused" do
      app = Fixtures::TestApp.new Label.new("hi"), 6, 2
      expect(app.frame).to be_nil
    end

    it "hides the cursor when the focused widget does not want it" do
      root = Box.new
      plain = Box.sized 2, 1
      root.add plain

      app = Fixtures::TestApp.new root, 6, 2
      app.focused = plain

      expect(app.frame).to be_nil
    end

    it "hides the cursor when the focused widget is hidden" do
      root = Box.new
      field = Box.sized 4, 1
      field.cursor = {0, 0}
      root.add field

      app = Fixtures::TestApp.new root, 6, 2
      app.focused = field
      field.hidden = true

      expect(app.frame).to be_nil
    end

    it "draws what the tree holds" do
      root = Box.new
      root.add Label.new("one"), Label.new("two")

      app = Fixtures::TestApp.new root, 6, 3
      expect(Fixtures.frame(app)).to eq ["one", "two", ""]
    end

    it "hands the cursor to whoever is painting" do
      root = Box.new
      field = Box.sized 3, 1
      field.cursor = {1, 0}
      root.add field

      app = Fixtures::TestApp.new root, 6, 2
      app.focused = field

      seen = [] of {Int32, Int32}?
      app.frame { |spot| seen << spot }

      expect(seen).to eq [{1, 0}]
    end
  end

  describe "#pump" do
    it "takes everything waiting and nothing more" do
      app = Fixtures::TestApp.new Label.new("hi"), 6, 2
      seen = [] of TermBuf::Event
      app.on_event = ->(event : TermBuf::Event) { seen << event; nil }

      app.events.send TermBuf::Events::Key.new(TermBuf::Key.character('a'), Bytes.empty)
      app.events.send TermBuf::Events::Key.new(TermBuf::Key.character('b'), Bytes.empty)

      expect(app.pump).to eq 2
      expect(app.pump).to eq 0
      expect(seen.size).to eq 2
    end

    it "answers nothing at all when the channel is empty" do
      app = Fixtures::TestApp.new Label.new("hi"), 6, 2
      expect(app.pump).to eq 0
    end
  end

  describe "a resize" do
    it "marks the tree dirty and lays it out at the new size" do
      root = Box.new
      label = Label.new "one two three"
      label.width = Sizing.grow
      root.add label

      app = Fixtures::TestApp.new root, 13, 4
      app.frame
      expect(label.rect.height).to eq 1
      expect(app.tree.dirty?).to be_false

      app.resized 7, 4
      app.pump

      expect(app.tree.dirty?).to be_true
      expect(Fixtures.frame(app)).to eq ["one two", "three", "", ""]
      expect(label.rect.height).to eq 2
    end

    it "leaves the tree alone when the size did not change" do
      app = Fixtures::TestApp.new Label.new("hi"), 6, 2
      app.frame

      app.resize TermBuf::Rect.full(6, 2)
      expect(app.tree.dirty?).to be_false
    end
  end
end
