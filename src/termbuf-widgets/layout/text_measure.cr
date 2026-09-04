require "./sizing"

module TermBuf::Widgets::Layout
  # Measuring a string in terminal cells, and breaking it into lines that fit.
  #
  # Everything here is byte ranges into the string it was measured from, so a
  # relayout at a new width costs no string building at all. Measurement runs
  # through `TermBuf::Unicode.each_grapheme` under a `WidthPolicy`, which is
  # what the terminal was probed for: the same emoji is one cell on one
  # terminal and two on the next, and a layout that guesses puts every later
  # column on the row in the wrong place. Always measure with the policy the
  # tree carries; never with the process-wide `Unicode.policy`.
  module TextMeasure
    extend self

    # A run of bytes on one line, and what it comes to in cells.
    record Line, start : Int32, bytesize : Int32, width : Int32 do
      # Cuts the run out of the string it was measured from.
      def text(source : String) : String
        source.byte_slice @start, @bytesize
      end

      # Whether the run covers no bytes.
      def empty? : Bool
        @bytesize.zero?
      end
    end

    # A run of non-whitespace, the whitespace in front of it, and the hard line
    # it sits on.
    record Word,
      start : Int32,
      bytesize : Int32,
      width : Int32,
      gap : Int32,
      line : Int32 do
      # Cuts the word out of the string it was measured from.
      def text(source : String) : String
        source.byte_slice @start, @bytesize
      end

      # One past the word's last byte.
      def stop : Int32
        @start + @bytesize
      end
    end

    # What a string came to, measured once.
    #
    # A widget keeps one of these and throws it away when its text or the
    # policy changes; `TextMeasure.wrap` then answers any width from it
    # without measuring again.
    struct Measured
      # What was measured.
      getter text : String

      # What it was measured against.
      getter policy : Unicode::WidthPolicy

      # Every run of non-whitespace, in order.
      getter words : Array(Word)

      # The text as written, split at its newlines. Never empty: a string with
      # no newline is one line, and an empty string is one empty line.
      getter hard_lines : Array(Line)

      # The widest single word, which is how narrow `Wrap::Words` can go
      # without splitting one.
      getter widest_word : Int32

      # The widest single grapheme cluster, which is how narrow anything can
      # go without splitting a cluster in half.
      getter widest_cluster : Int32

      # The widest hard line: what the text takes when nothing wraps it.
      getter width : Int32

      def initialize(@text : String, @policy : Unicode::WidthPolicy,
                     @words : Array(Word), @hard_lines : Array(Line),
                     @widest_word : Int32, @widest_cluster : Int32)
        @width = @hard_lines.max_of &.width
      end

      # Whether the text carries a newline of its own.
      def newlines? : Bool
        @hard_lines.size > 1
      end

      # Whether there is nothing to draw.
      def empty? : Bool
        @text.empty?
      end

      # How narrow this text can be laid out under *mode* without splitting
      # something that should not be split.
      def minimum(mode : Wrap) : Int32
        smallest = case mode
                   in .words?            then @widest_word
                   in .anywhere?, .none? then @widest_cluster
                   end

        Math.min smallest, @width
      end
    end

    # Measures *text* under *policy*.
    def measure(text : String, policy : Unicode::WidthPolicy) : Measured
      collector = Collector.new text
      Unicode.each_grapheme(text, policy) { |grapheme| collector.add grapheme }
      collector.finish policy
    end

    # Splits *measured* into lines of at most *width* cells under *mode*.
    #
    # A line can still come back wider than *width* when nothing narrower is
    # possible: a grapheme cluster is never cut in half, so a two-cell cluster
    # on a one-cell line overflows and the `TermBuf::View` cuts it later.
    def wrap(measured : Measured, width : Int32, mode : Wrap) : Array(Line)
      return blank_lines measured if width <= 0

      case mode
      in .none?     then measured.hard_lines
      in .anywhere? then wrap_anywhere measured, width
      in .words?    then wrap_words measured, width
      end
    end

    # How many rows *measured* takes at *width* under *mode*.
    def height(measured : Measured, width : Int32, mode : Wrap) : Int32
      wrap(measured, width, mode).size
    end

    # One empty line per hard line, for a width nothing can be drawn in.
    private def blank_lines(measured : Measured) : Array(Line)
      measured.hard_lines.map { |line| Line.new line.start, 0, 0 }
    end

    private def wrap_words(measured : Measured, width : Int32) : Array(Line)
      filler = Filler.new width, measured.text, measured.policy
      cursor = 0

      measured.hard_lines.each_with_index do |hard, index|
        filler.flush
        taken = false

        while cursor < measured.words.size && measured.words[cursor].line == index
          filler.add measured.words[cursor]
          cursor += 1
          taken = true
        end

        filler.blank hard unless taken
      end

      filler.flush
      filler.lines
    end

    private def wrap_anywhere(measured : Measured, width : Int32) : Array(Line)
      lines = [] of Line

      measured.hard_lines.each do |hard|
        if hard.empty?
          lines << hard
          next
        end

        lines.concat split_run(hard.text(measured.text), hard.start, width, measured.policy)
      end

      lines
    end

    # Breaks *run* into pieces of at most *width* cells, each one a `Line`
    # whose offsets are relative to a string in which *run* starts at byte
    # *offset*. Never returns nothing: an empty run is one empty line.
    #
    # A grapheme cluster is never cut. One that will not fit starts the next
    # piece instead, and one wider than the whole line gets a piece to itself
    # and overflows it.
    def split_run(run : String, offset : Int32, width : Int32,
                  policy : Unicode::WidthPolicy) : Array(Line)
      lines = [] of Line
      start = offset
      used = 0

      Unicode.each_grapheme(run, policy) do |grapheme|
        position = offset + grapheme.start

        if used > 0 && used + grapheme.width > width
          lines << Line.new start, position - start, used
          start = position
          used = 0
        end

        used += grapheme.width
      end

      lines << Line.new start, offset + run.bytesize - start, used
      lines
    end

    # Fills lines a word at a time, breaking one that is wider than the line
    # by cluster.
    private class Filler
      # The lines closed so far.
      getter lines = [] of Line

      @start : Int32 = -1
      @stop : Int32 = 0
      @used : Int32 = 0

      def initialize(@width : Int32, @source : String, @policy : Unicode::WidthPolicy)
      end

      # Puts *word* on the current line, or starts a new one for it.
      def add(word : Word) : Nil
        if @start < 0
          open word
          return
        end

        needed = @used + word.gap + word.width
        if needed <= @width
          @stop = word.stop
          @used = needed
        else
          flush
          open word
        end
      end

      # Keeps a hard line that has no words on it, so a blank line still takes
      # a row.
      def blank(hard : Line) : Nil
        @lines << Line.new hard.start, 0, 0
      end

      # Closes the current line, if there is one.
      def flush : Nil
        return if @start < 0

        @lines << Line.new @start, @stop - @start, @used
        @start = -1
        @used = 0
      end

      private def open(word : Word) : Nil
        return split word if word.width > @width

        @start = word.start
        @stop = word.stop
        @used = word.width
      end

      # A word too wide for a line of its own: full lines are closed as they
      # fill, and the tail is left open for whatever follows.
      private def split(word : Word) : Nil
        pieces = TextMeasure.split_run word.text(@source), word.start, @width, @policy
        tail = pieces.pop
        @lines.concat pieces
        @start = tail.start
        @stop = word.stop
        @used = tail.width
      end
    end

    # Walks the clusters of a string once, collecting words and hard lines.
    private class Collector
      @words = [] of Word
      @hard_lines = [] of Line
      @widest_word : Int32 = 0
      @widest_cluster : Int32 = 0

      @line_start : Int32 = 0
      @line_width : Int32 = 0
      @gap : Int32 = 0
      @first_on_line : Bool = true

      @word_start : Int32 = -1
      @word_stop : Int32 = 0
      @word_width : Int32 = 0

      def initialize(@text : String)
      end

      def add(grapheme : Unicode::Grapheme) : Nil
        char = grapheme.char

        if char == '\n'
          close_word
          close_line grapheme.start
          @line_start = grapheme.start + grapheme.bytesize
          return
        end

        if char && char.whitespace?
          close_word
          @gap += grapheme.width
          @line_width += grapheme.width
          return
        end

        @widest_cluster = grapheme.width if grapheme.width > @widest_cluster
        @word_start = grapheme.start if @word_start < 0
        @word_stop = grapheme.start + grapheme.bytesize
        @word_width += grapheme.width
        @line_width += grapheme.width
      end

      def finish(policy : Unicode::WidthPolicy) : Measured
        close_word
        close_line @text.bytesize

        Measured.new @text, policy, @words, @hard_lines, @widest_word, @widest_cluster
      end

      private def close_word : Nil
        return if @word_start < 0

        @words << Word.new @word_start, @word_stop - @word_start, @word_width,
          @first_on_line ? 0 : @gap, @hard_lines.size
        @widest_word = @word_width if @word_width > @widest_word
        @first_on_line = false
        @gap = 0
        @word_start = -1
        @word_width = 0
      end

      private def close_line(stop : Int32) : Nil
        @hard_lines << Line.new @line_start, stop - @line_start, @line_width
        @line_width = 0
        @gap = 0
        @first_on_line = true
      end
    end
  end
end
