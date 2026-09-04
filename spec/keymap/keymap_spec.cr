require "../spec_helper"

Spectator.describe Keymap do
  let(prefix) { ctrl 'v' }
  let(literal) { ctrl 'a' }
  let(save) { ctrl 's' }

  describe "#lookup" do
    let(keymap) do
      Keymap(Symbol).build do |map|
        map.bind save, "save the buffer", :save
        map.bind [prefix, literal], "insert the next key literally", :quote
      end
    end

    it "finds a whole sequence" do
      match, binding = keymap.lookup [save]
      expect(match).to eq Keymap::Match::Bound
      expect(binding.try(&.action)).to eq :save
    end

    it "finds a two key sequence" do
      match, binding = keymap.lookup [prefix, literal]
      expect(match).to eq Keymap::Match::Bound
      expect(binding.try(&.action)).to eq :quote
    end

    it "holds a prefix of a longer sequence" do
      match, binding = keymap.lookup [prefix]
      expect(match).to eq Keymap::Match::Pending
      expect(binding).to be_nil
    end

    it "knows a key nothing starts with" do
      match, binding = keymap.lookup [ctrl('z')]
      expect(match).to eq Keymap::Match::None
      expect(binding).to be_nil
    end

    it "knows a sequence that leaves the trie partway along" do
      match, _binding = keymap.lookup [prefix, ctrl('z')]
      expect(match).to eq Keymap::Match::None
    end

    it "knows a sequence that runs past a binding" do
      match, _binding = keymap.lookup [save, literal]
      expect(match).to eq Keymap::Match::None
    end

    it "reports an empty map as wanting nothing" do
      match, _binding = Keymap(Symbol).new.lookup [save]
      expect(match).to eq Keymap::Match::None
    end
  end

  describe "#bind" do
    it "refuses a key with no sequence" do
      expect do
        Keymap(Symbol).new.bind [] of Key, "nothing", :nothing
      end.to raise_error ArgumentError
    end

    it "refuses the same sequence twice" do
      keymap = Keymap(Symbol).new
      keymap.bind save, "save the buffer", :save

      expect { keymap.bind save, "write the file", :write }
        .to raise_error Keymap::Conflict, /already bound/
    end

    it "refuses a sequence that is a prefix of a bound one" do
      keymap = Keymap(Symbol).new
      keymap.bind [prefix, literal], "insert the next key literally", :quote

      expect { keymap.bind prefix, "prefix", :prefix }
        .to raise_error Keymap::Conflict, /is a prefix of/
    end

    it "names both sequences in the conflict" do
      keymap = Keymap(Symbol).new
      keymap.bind [prefix, literal], "insert the next key literally", :quote

      error = conflict { keymap.bind prefix, "prefix", :prefix }

      expect(error.attempted).to eq [prefix]
      expect(error.existing).to eq [prefix, literal]
    end

    it "refuses a sequence that extends a bound one" do
      keymap = Keymap(Symbol).new
      keymap.bind prefix, "prefix", :prefix

      expect { keymap.bind [prefix, literal], "quote", :quote }
        .to raise_error Keymap::Conflict, /extends the bound/
    end

    it "names both sequences when the new one is the longer" do
      keymap = Keymap(Symbol).new
      keymap.bind prefix, "prefix", :prefix

      error = conflict { keymap.bind [prefix, literal], "quote", :quote }

      expect(error.attempted).to eq [prefix, literal]
      expect(error.existing).to eq [prefix]
    end

    it "leaves the map alone when it refuses a binding" do
      keymap = Keymap(Symbol).new
      keymap.bind [prefix, literal], "quote", :quote

      expect { keymap.bind [ctrl('x'), ctrl('s'), ctrl('c')], "too long", :nope }.to_not raise_error
      expect { keymap.bind prefix, "prefix", :prefix }.to raise_error Keymap::Conflict

      match, _binding = keymap.lookup [prefix]
      expect(match).to eq Keymap::Match::Pending
      expect(keymap.bindings.size).to eq 2
    end
  end

  describe "aliases" do
    it "binds Ctrl+I as Tab" do
      keymap = Keymap(Symbol).new
      binding = keymap.bind ctrl('i'), "next field", :next_field

      expect(binding.keys).to eq [named(Key::Name::Tab)]
      expect(binding.to_s).to eq "Tab"
    end

    it "looks Tab up as Ctrl+I" do
      keymap = Keymap(Symbol).new
      keymap.bind named(Key::Name::Tab), "next field", :next_field

      match, binding = keymap.lookup [ctrl('i')]
      expect(match).to eq Keymap::Match::Bound
      expect(binding.try(&.action)).to eq :next_field
    end

    it "refuses Ctrl+I over Tab" do
      keymap = Keymap(Symbol).new
      keymap.bind named(Key::Name::Tab), "next field", :next_field

      expect { keymap.bind ctrl('i'), "indent", :indent }
        .to raise_error Keymap::Conflict, /already bound/
    end

    it "refuses Tab over Ctrl+I" do
      keymap = Keymap(Symbol).new
      keymap.bind ctrl('i'), "indent", :indent

      expect { keymap.bind named(Key::Name::Tab), "next field", :next_field }
        .to raise_error Keymap::Conflict, /already bound/
    end

    it "folds Ctrl+M onto Enter and Ctrl+H onto Backspace" do
      keymap = Keymap(Symbol).new
      keymap.bind ctrl('m'), "accept", :accept
      keymap.bind ctrl('h'), "rub out", :rub_out

      expect(keymap.bindings.map(&.keys.first)).to eq [
        named(Key::Name::Enter),
        named(Key::Name::Backspace),
      ]
    end

    it "folds the Ctrl+Backspace a terminal sends for 0x08 onto Backspace" do
      keymap = Keymap(Symbol).new
      keymap.bind named(Key::Name::Backspace), "rub out", :rub_out

      match, binding = keymap.lookup [Key.named(Key::Name::Backspace, Modifiers::Ctrl)]
      expect(match).to eq Keymap::Match::Bound
      expect(binding.try(&.action)).to eq :rub_out
    end

    it "keeps the other modifiers on an alias" do
      keymap = Keymap(Symbol).new
      binding = keymap.bind Key.character('i', Modifiers::Ctrl | Modifiers::Alt), "field", :field

      expect(binding.keys).to eq [Key.named(Key::Name::Tab, Modifiers::Alt)]
    end

    it "leaves a Ctrl letter that is not an alias alone" do
      keymap = Keymap(Symbol).new
      binding = keymap.bind save, "save", :save

      expect(binding.keys).to eq [save]
      expect(binding.to_s).to eq "Ctrl+S"
    end
  end

  describe "#bindings" do
    it "keeps them in the order they were defined" do
      keymap = Keymap(Symbol).build do |map|
        map.bind ctrl('z'), "suspend", :suspend
        map.bind save, "save the buffer", :save
        map.bind [prefix, literal], "quote", :quote
      end

      expect(keymap.bindings.map(&.action)).to eq [:suspend, :save, :quote]
      expect(keymap.bindings.map(&.description)).to eq [
        "suspend", "save the buffer", "quote",
      ]
    end
  end

  describe "#merge" do
    let(base) do
      Keymap(Symbol).build do |map|
        map.bind ctrl('z'), "suspend", :suspend
        map.bind save, "save the buffer", :save
      end
    end

    it "lets the other map win on an identical sequence" do
      overrides = Keymap(Symbol).build do |map|
        map.bind save, "write the file", :write
      end

      merged = base.merge overrides

      match, binding = merged.lookup [save]
      expect(match).to eq Keymap::Match::Bound
      expect(binding.try(&.action)).to eq :write
      expect(binding.try(&.description)).to eq "write the file"
    end

    it "overrides in place and appends what is new" do
      overrides = Keymap(Symbol).build do |map|
        map.bind save, "write the file", :write
        map.bind ctrl('q'), "quit", :quit
      end

      merged = base.merge overrides

      expect(merged.bindings.map(&.action)).to eq [:suspend, :write, :quit]
    end

    it "leaves both maps alone" do
      overrides = Keymap(Symbol).build do |map|
        map.bind ctrl('q'), "quit", :quit
      end

      base.merge overrides

      expect(base.bindings.size).to eq 2
      expect(overrides.bindings.size).to eq 1
    end

    it "still conflicts when the other map binds a prefix" do
      quoting = Keymap(Symbol).build do |map|
        map.bind [prefix, literal], "quote", :quote
      end

      shadowing = Keymap(Symbol).build do |map|
        map.bind prefix, "prefix", :prefix
      end

      expect { quoting.merge shadowing }.to raise_error Keymap::Conflict, /is a prefix of/
    end

    it "still conflicts when the other map extends a bound sequence" do
      shadowing = Keymap(Symbol).build do |map|
        map.bind prefix, "prefix", :prefix
      end

      quoting = Keymap(Symbol).build do |map|
        map.bind [prefix, literal], "quote", :quote
      end

      expect { shadowing.merge quoting }.to raise_error Keymap::Conflict, /extends the bound/
    end
  end
end
