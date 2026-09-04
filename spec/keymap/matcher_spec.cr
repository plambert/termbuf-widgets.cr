require "../spec_helper"

Spectator.describe Keymap::Matcher do
  let(prefix) { ctrl 'v' }
  let(literal) { ctrl 'a' }
  let(save) { ctrl 's' }
  let(matcher) { Keymap::Matcher.new }

  let(quoting) do
    Keymap(Symbol).build do |map|
      map.bind [prefix, literal], "insert the next key literally", :quote
      map.bind save, "save the buffer", :save
    end
  end

  describe "#feed" do
    it "fires a one key binding" do
      result = matcher.feed save, [quoting]

      expect(result.state).to eq Keymap::Matcher::State::Bound
      expect(result.bound?).to be_true
      expect(result.binding.try(&.action)).to eq :save
      expect(result.keymap).to be quoting
      expect(matcher.pending).to be_empty
    end

    it "holds a prefix and fires on the key that completes it" do
      held = matcher.feed prefix, [quoting]

      expect(held.pending?).to be_true
      expect(held.binding).to be_nil
      expect(matcher.pending).to eq [prefix]

      fired = matcher.feed literal, [quoting]

      expect(fired.bound?).to be_true
      expect(fired.binding.try(&.action)).to eq :quote
      expect(matcher.pending).to be_empty
    end

    it "drops a prefix when the next key is unbound, without replaying it" do
      matcher.feed prefix, [quoting]
      result = matcher.feed ctrl('z'), [quoting]

      expect(result.unbound?).to be_true
      expect(result.binding).to be_nil
      expect(result.keymap).to be_nil
      expect(matcher.pending).to be_empty
    end

    it "starts again after a dropped prefix" do
      matcher.feed prefix, [quoting]
      matcher.feed ctrl('z'), [quoting]

      result = matcher.feed save, [quoting]
      expect(result.binding.try(&.action)).to eq :save
    end

    it "leaves an ordinary character to the widget" do
      result = matcher.feed Key.character('a'), [quoting]

      expect(result.unbound?).to be_true
      expect(matcher.pending).to be_empty
    end

    it "wants nothing when there are no maps in scope" do
      result = matcher.feed save, [] of Keymap(Symbol)

      expect(result.unbound?).to be_true
    end

    it "normalises the key it is fed" do
      tabbing = Keymap(Symbol).build do |map|
        map.bind named(Key::Name::Tab), "next field", :next_field
      end

      result = matcher.feed ctrl('i'), [tabbing]

      expect(result.bound?).to be_true
      expect(result.binding.try(&.action)).to eq :next_field
    end

    it "holds a normalised prefix" do
      tabbing = Keymap(Symbol).build do |map|
        map.bind [named(Key::Name::Tab), literal], "reindent", :reindent
      end

      matcher.feed ctrl('i'), [tabbing]
      expect(matcher.pending).to eq [named(Key::Name::Tab)]

      result = matcher.feed literal, [tabbing]
      expect(result.binding.try(&.action)).to eq :reindent
    end
  end

  describe "#feed, along a chain of maps" do
    let(inner) do
      Keymap(Symbol).build do |map|
        map.bind save, "save this pane", :save_pane
      end
    end

    let(outer) do
      Keymap(Symbol).build do |map|
        map.bind save, "save everything", :save_all
        map.bind [prefix, literal], "quote", :quote
      end
    end

    it "lets the innermost map that binds the key win" do
      result = matcher.feed save, [inner, outer]

      expect(result.binding.try(&.action)).to eq :save_pane
      expect(result.keymap).to be inner
    end

    it "falls out to the enclosing map when the inner one has nothing" do
      result = matcher.feed save, [Keymap(Symbol).new, outer]

      expect(result.binding.try(&.action)).to eq :save_all
      expect(result.keymap).to be outer
    end

    it "holds for an enclosing map's prefix even when the inner map has nothing" do
      result = matcher.feed prefix, [inner, outer]

      expect(result.pending?).to be_true
      expect(matcher.pending).to eq [prefix]

      fired = matcher.feed literal, [inner, outer]
      expect(fired.binding.try(&.action)).to eq :quote
      expect(fired.keymap).to be outer
    end

    it "holds rather than firing an inner binding an outer sequence could extend" do
      shadowed = Keymap(Symbol).build do |map|
        map.bind prefix, "prefix on its own", :prefix
      end

      result = matcher.feed prefix, [shadowed, outer]

      expect(result.pending?).to be_true
    end
  end

  describe "#reset" do
    it "throws away a half typed sequence" do
      matcher.feed prefix, [quoting]
      matcher.reset

      expect(matcher.pending).to be_empty

      result = matcher.feed literal, [quoting]
      expect(result.unbound?).to be_true
    end
  end
end
