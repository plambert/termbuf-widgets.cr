module TermBuf::Widgets
  # Keys, bound to what they do to a `LineBuffer`.
  #
  # Bindings are data. `Action` names the vocabulary and a `Keymap` maps keys
  # to it, so an application rebinds by merging a map of its own rather than by
  # subclassing, and the enum is what documents what a field can be asked to
  # do.
  #
  # Anything the map does not want, that carries no modifier but shift, is text
  # and gets inserted. That rule is what keeps the map small.
  #
  # Keys go through a `Keymap::Matcher`, so a binding can be a sequence: the
  # first key of one is held rather than inserted, and a sequence that turns
  # out to be nothing at all is dropped rather than typed late.
  class Editor
    # Everything a key can be bound to.
    enum Action
      MoveLeft
      MoveRight
      MoveWordLeft
      MoveWordRight
      MoveHome
      MoveEnd

      SelectLeft
      SelectRight
      SelectWordLeft
      SelectWordRight
      SelectHome
      SelectEnd
      SelectAll

      DeleteBackward
      DeleteForward
      DeleteWordBackward
      DeleteWordForward

      KillToEnd
      KillToStart
      Yank
      Transpose

      HistoryPrevious
      HistoryNext

      Complete

      # Insert a line break, for a field that has room for one.
      Newline

      # Hand the line over and clear it.
      Accept

      # Give up on the line.
      Cancel

      # There is no more input coming, which is what `Ctrl+D` on an empty line
      # means and what an empty one does not.
      EndOfInput

      Clear
    end

    # What handling a key came to.
    enum Outcome
      # Nothing that concerns the caller.
      Continue

      # The line was accepted; `#accepted` has it.
      Accepted

      # The line was abandoned.
      Cancelled

      # There is no more input coming.
      Ended
    end

    # The readline bindings, because that is what fingers in a terminal expect.
    #
    # Key text goes through `TermBuf::Key.parse`, so what is written here is
    # normalised to what the decoder emits for the same press: `Ctrl+I` and
    # `Tab` are one key on the wire and one binding here, and binding both
    # would be a `Keymap::Conflict` rather than a map whose second entry never
    # fires. That is also why `Ctrl+H` is absent: it is the byte `Backspace`
    # already covers.
    DEFAULT_KEYMAP = Keymap(Action).build do |map|
      map.bind Key.parse("Left"), "one character left", Action::MoveLeft
      map.bind Key.parse("Right"), "one character right", Action::MoveRight
      map.bind Key.parse("Home"), "to the start of the line", Action::MoveHome
      map.bind Key.parse("End"), "to the end of the line", Action::MoveEnd
      map.bind Key.parse("Backspace"), "rub out the character before", Action::DeleteBackward
      map.bind Key.parse("Delete"), "rub out the character after", Action::DeleteForward
      map.bind Key.parse("Up"), "the line before", Action::HistoryPrevious
      map.bind Key.parse("Down"), "the line after", Action::HistoryNext
      map.bind Key.parse("Tab"), "complete the word", Action::Complete
      map.bind Key.parse("Enter"), "hand the line over", Action::Accept
      map.bind Key.parse("Escape"), "give up on the line", Action::Cancel

      map.bind Key.parse("Shift+Left"), "select one character left", Action::SelectLeft
      map.bind Key.parse("Shift+Right"), "select one character right", Action::SelectRight
      map.bind Key.parse("Shift+Home"), "select to the start of the line", Action::SelectHome
      map.bind Key.parse("Shift+End"), "select to the end of the line", Action::SelectEnd

      map.bind Key.parse("Ctrl+Left"), "one word left", Action::MoveWordLeft
      map.bind Key.parse("Ctrl+Right"), "one word right", Action::MoveWordRight

      map.bind Key.parse("Ctrl+A"), "to the start of the line", Action::MoveHome
      map.bind Key.parse("Ctrl+E"), "to the end of the line", Action::MoveEnd
      map.bind Key.parse("Ctrl+B"), "one character left", Action::MoveLeft
      map.bind Key.parse("Ctrl+F"), "one character right", Action::MoveRight
      map.bind Key.parse("Ctrl+K"), "kill to the end of the line", Action::KillToEnd
      map.bind Key.parse("Ctrl+U"), "kill to the start of the line", Action::KillToStart
      map.bind Key.parse("Ctrl+W"), "kill the word before", Action::DeleteWordBackward
      map.bind Key.parse("Ctrl+Y"), "put back what was killed", Action::Yank
      map.bind Key.parse("Ctrl+T"), "swap the two characters around the cursor", Action::Transpose
      map.bind Key.parse("Ctrl+P"), "the line before", Action::HistoryPrevious
      map.bind Key.parse("Ctrl+N"), "the line after", Action::HistoryNext
      map.bind Key.parse("Ctrl+L"), "empty the line", Action::Clear
      map.bind Key.parse("Ctrl+C"), "give up on the line", Action::Cancel
      map.bind Key.parse("Ctrl+D"), "end of input, or rub out after", Action::EndOfInput

      map.bind Key.parse("Alt+b"), "one word left", Action::MoveWordLeft
      map.bind Key.parse("Alt+f"), "one word right", Action::MoveWordRight
      map.bind Key.parse("Alt+d"), "kill the word after", Action::DeleteWordForward
    end

    # The text being edited.
    getter buffer : LineBuffer

    # Which key does what. A copy of `DEFAULT_KEYMAP` unless one was given.
    property keymap : Keymap(Action)

    # What holds the first keys of a sequence between presses.
    getter matcher = Keymap::Matcher.new

    # Lines entered earlier, or `nil` for a field that does not remember.
    property history : History?

    # What to ask when someone presses the completion key, or `nil` for a field
    # that does not complete.
    property completions : Completion::Hook?

    # Whether `Newline` inserts a break rather than being ignored.
    property? multiline : Bool

    # The line the last `Accepted` outcome handed over.
    getter accepted : String = ""

    # Candidates the last completion offered when there was more than one, for
    # a field to list. Emptied by anything else.
    getter candidates = [] of String

    # What the last completion came to, for a field to say something about.
    #
    # Without this an application cannot tell a completion that found nothing
    # from one that was never asked for: both leave no candidates behind. A
    # completion key that appears to do nothing is the usual result.
    enum Completed
      # Nothing has been asked for since the last edit.
      Idle

      # One candidate, and it went into the line.
      Inserted

      # Several candidates sharing nothing more; asking again lists them.
      Choices

      # The candidates are being listed.
      Listing

      # The hook was asked and offered nothing.
      Nothing
    end

    # What the last completion came to. Reset by the next edit.
    getter completion : Completed = Completed::Idle

    # Whether the candidates are worth showing, which they are only once the
    # completion key has been pressed twice with nothing chosen in between.
    def listing? : Bool
      @completion.listing?
    end

    def initialize(@buffer : LineBuffer = LineBuffer.new,
                   keymap : Keymap(Action)? = nil,
                   @history : History? = nil,
                   @completions : Completion::Hook? = nil,
                   @multiline : Bool = false)
      @keymap = keymap || Keymap(Action).new.merge(DEFAULT_KEYMAP)
    end

    # The line as it stands.
    def text : String
      @buffer.text
    end

    # Replaces the line and forgets where the history walk had got to.
    def text=(value : String) : String
      @buffer.replace value
      @history.try &.reset
      forget_completion
      value
    end

    # ------------------------------------------------------------- handling

    # Does whatever *key* is bound to, or inserts it when it is bound to
    # nothing and carries a character.
    #
    # A key that starts a sequence is held and nothing else happens until the
    # next one arrives. A sequence that goes nowhere is dropped, and only the
    # key that ended it is offered to the insert rule: the keys held on the
    # promise of a binding were typed as a command, and putting them in the
    # line late is worse than losing them.
    def handle(key : Key) : Outcome
      result = @matcher.feed key, [@keymap]
      return Outcome::Continue if result.pending?

      binding = result.binding
      return perform binding.action if binding
      return Outcome::Continue unless insertable? key

      forget_completion
      @history.try &.reset
      @buffer.insert key.char
      Outcome::Continue
    end

    # Pasted text goes in as text, whatever it contains. A field with no room
    # for a line break flattens them rather than dropping the rest.
    def paste(text : String) : Outcome
      forget_completion
      @history.try &.reset
      @buffer.insert @multiline ? text : text.gsub(/\r\n|[\r\n]/, " ")
      Outcome::Continue
    end

    # A key with nothing but shift held, carrying a character, is text.
    private def insertable?(key : Key) : Bool
      return false unless key.character?
      return false unless (key.modifiers & ~Modifiers::Shift).none?

      key.char >= ' '
    end

    private def perform(action : Action) : Outcome
      forget_completion unless action.complete?

      case action
      when .accept?           then return accept
      when .cancel?           then return Outcome::Cancelled
      when .end_of_input?     then return @buffer.empty? ? Outcome::Ended : delete_forward
      when .complete?         then complete
      when .history_previous? then recall(-1)
      when .history_next?     then recall 1
      else                         edit action
      end

      Outcome::Continue
    end

    private def accept : Outcome
      @accepted = @buffer.text
      @history.try &.add @accepted
      @buffer.clear
      Outcome::Accepted
    end

    private def delete_forward : Outcome
      @buffer.delete_forward
      Outcome::Continue
    end

    # ameba:disable Metrics/CyclomaticComplexity
    private def edit(action : Action) : Nil
      touched = true

      case action
      when .move_left?            then @buffer.move_left
      when .move_right?           then @buffer.move_right
      when .move_word_left?       then @buffer.move_word_left
      when .move_word_right?      then @buffer.move_word_right
      when .move_home?            then @buffer.move_home
      when .move_end?             then @buffer.move_end
      when .select_left?          then @buffer.select_to @buffer.cursor - 1
      when .select_right?         then @buffer.select_to @buffer.cursor + 1
      when .select_word_left?     then @buffer.select_to @buffer.word_left
      when .select_word_right?    then @buffer.select_to @buffer.word_right
      when .select_home?          then @buffer.select_to @buffer.line_start
      when .select_end?           then @buffer.select_to @buffer.line_end
      when .select_all?           then @buffer.select_all
      when .delete_backward?      then @buffer.delete_backward
      when .delete_forward?       then @buffer.delete_forward
      when .delete_word_backward? then @buffer.kill_word_backward
      when .delete_word_forward?  then @buffer.kill_word_forward
      when .kill_to_end?          then @buffer.kill_to_end
      when .kill_to_start?        then @buffer.kill_to_start
      when .yank?                 then @buffer.yank
      when .transpose?            then @buffer.transpose
      when .clear?                then @buffer.clear
      when .newline?              then insert_newline
      else                             touched = false
      end

      # A motion does not end a history walk; changing the line does, because
      # stepping back onto an entry that has been edited would lose the edit.
      @history.try &.reset if touched && changes? action
    end

    private def insert_newline : Nil
      @buffer.insert "\n" if @multiline
    end

    private def changes?(action : Action) : Bool
      !action.to_s.starts_with?("Move") && !action.to_s.starts_with?("Select")
    end

    # ------------------------------------------------------------- history

    private def recall(direction : Int32) : Nil
      history = @history
      return unless history

      line = direction < 0 ? history.previous(@buffer.text) : history.next
      return unless line

      @buffer.replace line
    end

    # ---------------------------------------------------------- completion

    # The word under the cursor, by the buffer's own idea of what a word is.
    def word_range : Range(Int32, Int32)
      cursor = @buffer.cursor
      start = cursor

      while start > 0 && @buffer.word.call(@buffer[start - 1] || "")
        start -= 1
      end

      start...cursor
    end

    private def complete : Nil
      hook = @completions
      return unless hook

      range = word_range
      result = hook.call Completion::Request.new(@buffer.text, @buffer.cursor,
        @buffer.slice(range), range)
      return apply_nothing if result.empty?

      apply result, range
    end

    private def apply(result : Completion::Result, fallback : Range(Int32, Int32)) : Nil
      range = result.range || fallback
      prefix = Completion.common_prefix result.candidates

      unless prefix.empty? || prefix == @buffer.slice(range)
        @buffer.delete range
        @buffer.insert prefix
      end

      if result.candidates.size == 1
        @candidates = [] of String
        @completion = Completed::Inserted
        return
      end

      # One press inserts what is common; the second says there was a choice
      # and shows it. Listing on the first press is noise on a line that only
      # ever had one answer.
      @candidates = result.candidates
      @completion = if @completion.choices? || @completion.listing?
                      Completed::Listing
                    else
                      Completed::Choices
                    end
    end

    private def apply_nothing : Nil
      @candidates = [] of String
      @completion = Completed::Nothing
    end

    private def forget_completion : Nil
      return if @completion.idle?

      @candidates = [] of String
      @completion = Completed::Idle
    end
  end
end
