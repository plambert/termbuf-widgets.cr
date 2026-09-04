require "../spec_helper"

Spectator.describe TermBuf::Widgets::Field do
  alias Field = TermBuf::Widgets::Field
  alias Editor = TermBuf::Widgets::Editor
  alias Completion = TermBuf::Widgets::Completion
  alias Growth = TermBuf::Widgets::Field::Growth
  alias Name = TermBuf::Key::Name

  def field(text : String = "", **options) : Field
    made = Field.new(**options)
    made.text = text
    made
  end

  # A field is put in a panel rather than made the root, because the root is
  # given the whole screen whatever its sizing says and these cases are about
  # what the field asks for.
  def panel(made : Field) : Fixtures::Box
    held = made.parent
    return held if held.is_a? Fixtures::Box

    root = Fixtures::Box.new
    root.add made
    root
  end

  # Lays *made* out at the top of a screen this size and draws it.
  def render(made : Field, columns : Int32 = 30, rows : Int32 = 6) : Array(String)
    Fixtures.render panel(made), columns, rows
  end

  # Lays it out without drawing, which is what the geometry cases want.
  def settle(made : Field, columns : Int32 = 30, rows : Int32 = 6) : Field
    Layout::Tree.new(panel(made), Rect.full(columns, rows)).layout
    made
  end

  def type(made : Field, text : String) : Nil
    text.each_char { |char| made.press TermBuf::Key.character(char) }
  end

  def press(made : Field, name : Name, modifiers = TermBuf::Modifiers::None) : Nil
    made.press TermBuf::Key.named(name, modifiers)
  end

  def completing(candidates : Array(String), **options) : Field
    Field.new(**options, editor: Editor.new(completions: ->(_request : Completion::Request) do
      Completion::Result.new candidates
    end))
  end

  describe "drawing" do
    it "shows the text with the prompt in front of it" do
      made = field "hello", prompt: Field::Prompt.new("> ")

      expect(render(made, 20, 1).first).to eq "> hello"
    end

    it "draws a border around itself" do
      made = field "hi", border: TermBuf::Widgets::Border.plain

      expect(render(made, 8, 3)).to eq ["┌──────┐", "│hi    │", "└──────┘"]
    end

    it "shows the placeholder while there is nothing to show" do
      made = field placeholder: "type here"

      expect(render(made, 20, 1).first).to eq "type here"

      made.text = "x"
      expect(render(made, 20, 1).first).to eq "x"
    end
  end

  describe "a fixed field" do
    it "stays one row however long the text is" do
      made = settle field("a" * 50), 10, 6

      expect(made.text_rows).to eq 1
      expect(made.rect.height).to eq 1
    end

    # What is off the edge should be visible as missing rather than merely
    # absent.
    it "scrolls sideways and marks what is off the edge" do
      made = field
      type made, "abcdefghijklmno"

      line = render(made, 10, 1).first
      expect(line.starts_with? "<").to be_true
      expect(line).to contain "o"
    end

    it "scrolls back when the cursor goes left again" do
      made = field
      type made, "abcdefghijklmno"
      render made, 10, 1
      press made, Name::Home

      expect(render(made, 10, 1).first.starts_with? "a").to be_true
      expect(made.offset).to eq 0
    end

    it "flattens a pasted line break" do
      made = field
      made.paste "one\ntwo"

      expect(made.text).to eq "one two"
    end
  end

  describe "a growing field" do
    it "wraps at the right edge and asks for the rows it needs" do
      made = settle field("abcdefgh", growth: Growth::Grow, max_rows: 8), 4, 6

      expect(made.rows.size).to eq 3
      expect(made.rect.height).to eq 3
    end

    it "never splits a wide cluster across the edge" do
      made = field "a漢漢", growth: Growth::Grow

      expect(render(made, 4, 3).first(2)).to eq ["a漢", "漢"]
    end

    it "keeps a line break where it was put" do
      made = field "one\ntwo", growth: Growth::Grow

      expect(render(made, 10, 2).first(2)).to eq ["one", "two"]
    end

    it "indents the rows after the first under the prompt" do
      made = field "abcde",
        prompt: Field::Prompt.new("> ", continuation: ".."),
        growth: Growth::Grow

      expect(render(made, 5, 2).first(2)).to eq ["> abc", "..de"]
    end

    # Text that exactly fills a row leaves the cursor with nowhere to go, so
    # the row it will type into has to exist.
    it "asks for a row to put the cursor on after a full one" do
      made = settle field("abcd", growth: Growth::Grow), 4, 6

      expect(made.rows.size).to eq 2
      expect(made.rect.height).to eq 2
    end

    # A view too short for the text follows the cursor rather than showing the
    # top and losing it.
    it "scrolls to keep the cursor in view" do
      made = field "abcdefghi", growth: Growth::Grow, max_rows: 2

      expect(render(made, 3, 2).first(2)).to eq ["ghi", ""]
      made.buffer.move_to 0

      expect(render(made, 3, 2).first(2)).to eq ["abc", "def"]
    end

    it "stops growing at the rows it was allowed" do
      made = settle field("a" * 40, growth: Growth::Grow, max_rows: 3), 5, 8

      expect(made.rect.height).to eq 3
    end
  end

  describe "#cursor_position" do
    it "sits where the next character goes" do
      made = field prompt: Field::Prompt.new("> ")
      settle made, 20, 1
      type made, "abc"

      expect(made.cursor_position).to eq({5, 0})
    end

    it "allows for a wide cluster in front of it" do
      made = field
      settle made, 20, 1
      type made, "漢"

      expect(made.cursor_position).to eq({2, 0})
    end

    it "answers inside its own border" do
      made = settle field("ab", border: TermBuf::Widgets::Border.plain), 10, 3

      expect(made.cursor_position).to eq({2, 0})
      expect(made.content.x).to eq 1
      expect(made.content.y).to eq 1
    end

    # A cursor after a row that is exactly full belongs at the start of the
    # next one, not off the right edge of the one above.
    it "drops to the next row after a full one" do
      made = settle field("abcd", growth: Growth::Grow), 4, 3

      expect(made.cursor_position).to eq({0, 1})
    end

    it "is where the app puts the terminal's cursor" do
      made = field "ab", border: TermBuf::Widgets::Border.plain
      app = Fixtures::TestApp.new panel(made), 10, 3
      app.frame
      app.focus.focus made

      expect(app.frame).to eq({3, 1})
    end
  end

  describe "selection" do
    it "draws what is selected differently" do
      made = field "hello"
      settle made, 10, 1
      made.buffer.move_to 0
      3.times { press made, Name::Right, TermBuf::Modifiers::Shift }

      expect(made.buffer.selected_text).to eq "hel"
      expect(render(made, 10, 1).first).to eq "hello"
    end
  end

  describe "completion" do
    it "grows to list the candidates once they are worth listing" do
      made = settle completing(["commit", "commander"]), 20, 6
      type made, "co"
      2.times { press made, Name::Tab }
      settle made, 20, 6

      expect(made.editor.listing?).to be_true
      expect(made.rect.height).to be > 1
    end

    # A completion key that finds nothing and a completion key that is not
    # bound look exactly alike unless the field says which happened.
    it "says so when nothing matched" do
      made = completing [] of String
      settle made, 20, 6
      type made, "zzz"
      press made, Name::Tab

      lines = render made, 20, 6
      expect(lines[0]).to eq "zzz"
      expect(lines[1]).to contain "no match"
    end

    it "says how many there are before it lists them" do
      made = completing ["commit", "commander"]
      settle made, 24, 6
      type made, "co"
      press made, Name::Tab

      expect(made.editor.completion.choices?).to be_true
      expect(render(made, 24, 6)[1]).to contain "2 matches"
    end

    it "says nothing once a single candidate has gone in" do
      made = completing ["commit"]
      settle made, 20, 6
      type made, "co"
      press made, Name::Tab

      lines = render made, 20, 6
      expect(lines[0]).to eq "commit"
      expect(lines[1]).to eq ""
      expect(made.rect.height).to eq 1
    end

    it "takes the note back at the next keystroke" do
      made = completing [] of String
      settle made, 20, 6
      type made, "zzz"
      press made, Name::Tab
      type made, "x"

      expect(made.editor.completion.idle?).to be_true
      expect(render(made, 20, 6)[1]).to eq ""
    end

    it "keeps Tab for itself when it can complete" do
      made = completing ["commit"]
      app = Fixtures::TestApp.new made, 20, 4
      app.frame
      Fixtures.type app, "co"
      Fixtures.press app, "Tab"

      expect(made.text).to eq "commit"
    end

    it "leaves Tab alone when it cannot" do
      root = Fixtures::Box.new
      first = Field.new
      second = Field.new
      root.add first, second

      app = Fixtures::TestApp.new root, 20, 4
      app.frame
      expect(app.focused).to be first

      Fixtures.press app, "Tab"
      expect(app.focused).to be second
    end
  end

  describe "handling events" do
    def wired : {Fixtures::TestApp, Field, Fixtures::Box}
      root = Fixtures::Box.new
      made = Field.new
      root.add made
      app = Fixtures::TestApp.new root, 20, 4
      app.frame
      app.focus.focus made

      {app, made, root}
    end

    it "takes a key and claims it" do
      app, made, root = wired
      Fixtures.type app, "hi"

      expect(made.text).to eq "hi"
      expect(root.seen).to be_empty
    end

    it "takes a paste" do
      app, made, _ = wired
      app.events.send TermBuf::Events::Paste.new("pasted", true)
      app.pump

      expect(made.text).to eq "pasted"
    end

    # A paste is news about the terminal as much as it is text, and whatever is
    # showing a notice about it needs to hear that it ended.
    it "lets a paste carry on to whatever is above it" do
      app, made, root = wired
      app.events.send TermBuf::Events::Paste.new("pasted", true)
      app.pump

      expect(made.text).to eq "pasted"
      expect(root.seen.map(&.class)).to eq [TermBuf::Events::Paste]
    end

    it "leaves anything that is not input alone" do
      app, made, root = wired
      app.events.send TermBuf::Events::Warning.new("something")
      app.pump

      expect(made.text).to be_empty
      expect(root.seen.size).to eq 1
    end

    it "asks for a layout again when the text changed" do
      app, _, _ = wired
      expect(app.tree.dirty?).to be_false

      Fixtures.type app, "a"
      expect(app.tree.dirty?).to be_true
    end
  end

  describe "what it says when the line is over" do
    def wired : {Fixtures::TestApp, Field, Fixtures::Box}
      root = Fixtures::Box.new
      made = Field.new
      root.add made
      app = Fixtures::TestApp.new root, 20, 4
      app.frame
      app.focus.focus made

      {app, made, root}
    end

    it "hands the line over when it is accepted" do
      app, made, root = wired
      Fixtures.type app, "one"
      Fixtures.press app, "Enter"
      app.pump

      accepted = root.seen.compact_map(&.as?(Field::Accepted))
      expect(accepted.map(&.text)).to eq ["one"]
      expect(made.text).to be_empty
    end

    it "says so when the line is abandoned" do
      app, _, root = wired
      Fixtures.type app, "one"
      Fixtures.press app, "Escape"
      app.pump

      expect(root.seen.count(&.is_a?(Field::Cancelled))).to eq 1
    end

    it "says so when there is no more input coming" do
      app, _, root = wired
      Fixtures.press app, "Ctrl+D"
      app.pump

      expect(root.seen.count(&.is_a?(Field::EndOfInput))).to eq 1
    end

    it "says nothing while the line is still being typed" do
      app, _, root = wired
      Fixtures.type app, "one"
      app.pump

      expect(root.seen.count(&.is_a?(TermBuf::Widgets::Message))).to eq 0
    end
  end
end
