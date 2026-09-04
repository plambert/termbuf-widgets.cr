require "../spec_helper"

Spectator.describe Layout::TextMeasure do
  alias Measure = Layout::TextMeasure
  alias Wrap = Layout::Wrap

  let(policy) { TermBuf::Unicode::WidthPolicy::DEFAULT }

  def measure(text : String) : Measure::Measured
    Measure.measure text, TermBuf::Unicode::WidthPolicy::DEFAULT
  end

  def wrapped(text : String, width : Int32, mode : Wrap) : Array(String)
    measured = measure text
    Measure.wrap(measured, width, mode).map &.text(text)
  end

  def widths(text : String, width : Int32, mode : Wrap) : Array(Int32)
    Measure.wrap(measure(text), width, mode).map &.width
  end

  describe ".measure" do
    it "finds the words and what sits between them" do
      measured = measure "the quick brown"

      expect(measured.words.map(&.text("the quick brown"))).to eq ["the", "quick", "brown"]
      expect(measured.words.map(&.width)).to eq [3, 5, 5]
      expect(measured.words.map(&.gap)).to eq [0, 1, 1]
      expect(measured.width).to eq 15
    end

    it "measures a wide cluster as the cells it takes" do
      measured = measure "字字 a"

      expect(measured.words.map(&.width)).to eq [4, 1]
      expect(measured.widest_word).to eq 4
      expect(measured.widest_cluster).to eq 2
      expect(measured.width).to eq 6
    end

    it "measures a joined emoji as one cluster" do
      measured = measure "👩‍👩‍👧x"

      expect(measured.widest_cluster).to eq 2
      expect(measured.width).to eq 3
      expect(measured.words.size).to eq 1
    end

    it "keeps the whole run of spaces between two words" do
      measured = measure "aa   bb"

      expect(measured.words.map(&.gap)).to eq [0, 3]
      expect(measured.width).to eq 7
    end

    it "splits at newlines and starts each line's gap again" do
      measured = measure "ab\ncd ef"

      expect(measured.hard_lines.map(&.text("ab\ncd ef"))).to eq ["ab", "cd ef"]
      expect(measured.words.map(&.line)).to eq [0, 1, 1]
      expect(measured.words.map(&.gap)).to eq [0, 0, 1]
      expect(measured.newlines?).to be_true
      expect(measured.width).to eq 5
    end

    it "keeps a blank line between two others" do
      measured = measure "ab\n\ncd"

      expect(measured.hard_lines.size).to eq 3
      expect(measured.hard_lines[1].width).to eq 0
    end

    it "keeps the empty line a trailing newline leaves behind" do
      expect(measure("ab\n").hard_lines.size).to eq 2
    end

    it "makes one empty line of an empty string" do
      measured = measure ""

      expect(measured.words).to be_empty
      expect(measured.hard_lines.size).to eq 1
      expect(measured.width).to eq 0
      expect(measured.newlines?).to be_false
    end

    it "counts leading whitespace in the unwrapped width" do
      expect(measure("  ab").width).to eq 4
    end
  end

  describe "#minimum" do
    it "is the widest word when words are kept whole" do
      expect(measure("aa bbbb").minimum(Wrap::Words)).to eq 4
    end

    it "is the widest cluster when anything may break" do
      expect(measure("aa 字bbb").minimum(Wrap::Anywhere)).to eq 2
    end

    it "is the widest cluster when nothing wraps at all" do
      expect(measure("aa bbbb").minimum(Wrap::None)).to eq 1
    end

    it "never exceeds the unwrapped width" do
      expect(measure("ab").minimum(Wrap::Words)).to eq 2
    end
  end

  describe ".wrap in Words mode" do
    it "fills each line and starts a new one for what will not fit" do
      expect(wrapped("aa bb cc", 5, Wrap::Words)).to eq ["aa bb", "cc"]
      expect(widths("aa bb cc", 5, Wrap::Words)).to eq [5, 2]
    end

    it "puts everything on one line when it fits" do
      expect(wrapped("aa bb cc", 8, Wrap::Words)).to eq ["aa bb cc"]
    end

    it "counts the whole run of spaces when deciding what fits" do
      expect(wrapped("aa   bb", 6, Wrap::Words)).to eq ["aa", "bb"]
      expect(wrapped("aa   bb", 7, Wrap::Words)).to eq ["aa   bb"]
    end

    it "breaks a word wider than the line by cluster" do
      expect(wrapped("abcdef", 3, Wrap::Words)).to eq ["abc", "def"]
    end

    it "carries on the line the tail of a broken word left open" do
      expect(wrapped("abcde f", 4, Wrap::Words)).to eq ["abcd", "e f"]
    end

    it "never straddles a wide cluster when it breaks a word" do
      expect(wrapped("字字字", 3, Wrap::Words)).to eq ["字", "字", "字"]
      expect(widths("字字字", 3, Wrap::Words)).to eq [2, 2, 2]
    end

    it "overflows rather than cutting a cluster in half" do
      expect(widths("字", 1, Wrap::Words)).to eq [2]
    end

    it "breaks at every newline whatever the width" do
      expect(wrapped("ab\ncd", 20, Wrap::Words)).to eq ["ab", "cd"]
    end

    it "keeps a blank line" do
      expect(wrapped("ab\n\ncd", 20, Wrap::Words)).to eq ["ab", "", "cd"]
    end

    it "gives an empty string one empty line" do
      expect(wrapped("", 10, Wrap::Words)).to eq [""]
    end
  end

  describe ".wrap in Anywhere mode" do
    it "packs clusters up to the width" do
      expect(wrapped("abcdefg", 3, Wrap::Anywhere)).to eq ["abc", "def", "g"]
    end

    it "never straddles a wide cluster" do
      expect(wrapped("字字字", 3, Wrap::Anywhere)).to eq ["字", "字", "字"]
    end

    it "starts the next line rather than cutting a cluster that will not fit" do
      expect(wrapped("ab字", 3, Wrap::Anywhere)).to eq ["ab", "字"]
    end

    it "breaks inside a word" do
      expect(wrapped("aa bb", 3, Wrap::Anywhere)).to eq ["aa ", "bb"]
    end

    it "breaks at every newline as well" do
      expect(wrapped("abc\ndef", 10, Wrap::Anywhere)).to eq ["abc", "def"]
    end
  end

  describe ".wrap in None mode" do
    it "leaves the text unwrapped however narrow the line" do
      expect(wrapped("aaa bbb", 2, Wrap::None)).to eq ["aaa bbb"]
      expect(widths("aaa bbb", 2, Wrap::None)).to eq [7]
    end

    it "takes its height from the newlines and nowhere else" do
      expect(wrapped("ab\ncd\nef", 1, Wrap::None)).to eq ["ab", "cd", "ef"]
    end
  end

  describe ".wrap with no room at all" do
    it "gives one empty line per hard line" do
      expect(wrapped("ab cd\nef", 0, Wrap::Words)).to eq ["", ""]
      expect(wrapped("ab cd\nef", -3, Wrap::Anywhere)).to eq ["", ""]
    end
  end

  describe ".height" do
    it "counts the lines the text breaks into" do
      measured = measure "aa bb cc dd"

      expect(Measure.height(measured, 5, Wrap::Words)).to eq 2
      expect(Measure.height(measured, 11, Wrap::Words)).to eq 1
      expect(Measure.height(measured, 2, Wrap::None)).to eq 1
    end
  end
end
