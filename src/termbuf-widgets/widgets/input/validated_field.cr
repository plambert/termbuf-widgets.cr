require "../../message"
require "../../router"
require "../field"
require "./validators"

module TermBuf::Widgets
  # A `Field` that holds the line to a set of rules before it hands it over.
  #
  #     field = ValidatedField.new prompt: Field::Prompt.new("port: ")
  #     field.validators << Validators.required
  #     field.validators << Validators.numeric
  #
  # The rules are asked when the line is accepted, and on every keystroke as
  # well when `#validate_on_change?`. A line that passes leaves as
  # `Field::Accepted`, exactly as it would from a field with no rules; a line
  # that does not leaves as `Invalid` instead, carrying every message the rules
  # had, and the field draws the first of them under the line.
  #
  # A refused line stays in the field. The editor clears the buffer when it
  # accepts, which is right for a prompt that starts again and wrong here: a
  # user asked to correct an entry has to have the entry in front of them, so
  # it is put back.
  class ValidatedField < Field
    # The line was handed over and the rules refused it. Sent instead of
    # `Field::Accepted`, never as well as it.
    struct Invalid < Message
      # Which field it was.
      getter field : ValidatedField

      # What was entered, which is still in the field.
      getter text : String

      # What every rule that refused it had to say, in the order they were
      # asked.
      getter errors : Array(String)

      def initialize(@field : ValidatedField, @text : String, @errors : Array(String))
      end

      # The first message, which is the one the field draws.
      def message : String?
        @errors.first?
      end
    end

    # The rules the line is held to, asked in order.
    property validators : Array(Validator)

    # Whether the rules are asked at every keystroke as well as at the end.
    #
    # Off by default: telling somebody their entry is too short while they are
    # still typing it is a complaint about work in progress. Turn it on for a
    # field whose answer is wrong rather than unfinished as it is typed, such
    # as one that takes a number.
    property? validate_on_change : Bool

    # What the rules said the last time they were asked, in the order they were
    # asked. Empty when the line passed or has not been held to them.
    getter errors : Array(String) = [] of String

    # What the message under the line is drawn in.
    property error_style : Style

    def initialize(*args, validators : Array(Validator)? = nil,
                   validate_on_change : Bool = false,
                   error_style : Style = Style::DEFAULT.fg(Color::RED),
                   **options)
      @validators = validators || [] of Validator
      @validate_on_change = validate_on_change
      @error_style = error_style
      super *args, **options
    end

    # Every rule's answer to the line as it stands.
    def validate : Array(String)
      validate text
    end

    # Every rule's answer to *text*.
    def validate(text : String) : Array(String)
      @validators.compact_map &.call(text)
    end

    # The message drawn under the line, or `nil` when there is none.
    def error : String?
      @errors.first?
    end

    # Whether the last answer the rules gave was a refusal.
    def invalid? : Bool
      !@errors.empty?
    end

    # Takes the message away, which is what a field being filled in again
    # wants.
    def clear_error : Nil
      remember [] of String
    end

    # Replaces the line and forgets whatever the rules last said about it.
    def text=(value : String) : String
      clear_error
      super
    end

    # ------------------------------------------------------------- events

    # Does whatever *key* is bound to and says what came of it.
    #
    # `Field#press` is not called, because what happens to an accepted line is
    # the whole of what this class changes and the field emits it directly.
    def press(key : Key) : Nil
      settle @editor.handle key
    end

    # Pasted text goes in as text, and counts as a change.
    def paste(text : String) : Nil
      settle @editor.paste text
    end

    private def settle(outcome : Editor::Outcome) : Nil
      # The text changed, and how tall the field wants to be changes with it.
      invalidate_layout

      case outcome
      in .continue?  then remember validate if @validate_on_change
      in .accepted?  then finish @editor.accepted
      in .cancelled? then emit Field::Cancelled.new
      in .ended?     then emit Field::EndOfInput.new
      end
    end

    # What becomes of a line the editor has accepted and taken out of the
    # buffer.
    private def finish(entered : String) : Nil
      found = validate entered

      if found.empty?
        clear_error
        emit Field::Accepted.new entered
        return
      end

      # Back it goes: the field is asking for a correction, and there is
      # nothing to correct once the line has been cleared. `Field#text=` puts
      # the cursor at the end of it, which is where a correction usually
      # starts.
      restore entered
      remember found
      emit Invalid.new self, entered, found
    end

    # `Field#text=` without this class's clearing of the message, since the
    # message is what is about to be set.
    private def restore(value : String) : Nil
      @editor.text = value
      invalidate_layout
    end

    # Keeps *found* as what the rules said, and lays out again when that
    # changes: a message takes a row the line cannot have.
    private def remember(found : Array(String)) : Nil
      return if @errors == found

      @errors = found
      invalidate_layout
    end

    # ------------------------------------------------------------- layout

    # A row for the message, on top of whatever the line itself wants.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      super + error_rows
    end

    # The message takes its row off the bottom, the way a completion listing
    # does.
    def visible_rows : Int32
      Math.max super - error_rows, 1
    end

    private def error_rows : Int32
      @errors.empty? ? 0 : 1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      super
      draw_error view
    end

    # Writes the message on the bottom row of the box, where the row reserved
    # by `#visible_rows` is.
    protected def draw_error(view : View) : Nil
      message = error
      return if message.nil? || view.width <= 0 || view.height <= 0

      view.write 0, view.height - 1,
        Unicode.truncate(message, view.width, view.policy), @error_style
    end
  end
end
