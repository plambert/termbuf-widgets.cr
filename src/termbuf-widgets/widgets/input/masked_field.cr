require "../field"
require "./interactive"
require "./validated_field"

module TermBuf::Widgets
  # A field that draws a mark for every character instead of the character.
  #
  #     field = MaskedField.new prompt: Field::Prompt.new("password: ")
  #     field.validators << Validators.length(min: 8)
  #
  # `#value` is the text as typed, which is what the application wants and what
  # nothing on the screen shows. `#reveal?` turns the masking off, for the eye
  # that every password box has next to it now.
  #
  # It is a `ValidatedField` rather than a `Field` because the two go together:
  # a box nobody can read is the one place where a rule about what was typed
  # has to be enforced by something other than the user's eyes. A masked field
  # with no rules behaves exactly as a plain one.
  #
  # The mask is measured before it is used, the way a `Checkbox`'s marks are: a
  # bullet is one cell on a terminal that measures it the way the standard says
  # and two on one that does not, and a row of them laid out for the first and
  # drawn on the second overflows the field.
  #
  # Masking is a drawing rule and not a storage one. The text is in the buffer
  # as it was typed, so the kill ring and a paste out of the field carry it;
  # this hides a password from somebody looking over a shoulder, and it is not
  # a secret store.
  class MaskedField < ValidatedField
    # What each character is drawn as where the terminal measures it at one
    # cell.
    MASK = "•"

    # What it is drawn as everywhere else.
    ASCII_MASK = "*"

    # The mark to draw, or `nil` to measure and choose.
    layout_property mask : String? = nil

    # Whether the text is shown as it was typed.
    layout_property? reveal : Bool = false

    # Clusters the view has scrolled past, which for a mask is a count of
    # marks rather than of cells.
    getter mask_offset : Int32 = 0

    def initialize(*args, mask : String? = nil, reveal : Bool = false, **options)
      @mask = mask
      @reveal = reveal
      super *args, **options
      # A masked field is one row: there is nothing to be gained by wrapping a
      # line nobody can read, and a great deal of drawing to get wrong.
      self.growth = Field::Growth::Fixed
      @editor.multiline = false
    end

    # The text as it was typed, which is what nothing on the screen shows.
    def value : String
      text
    end

    # :ditto:
    def value=(entered : String) : String
      self.text = entered
    end

    # The mark this field draws: the one it was given, or whichever spelling
    # suits the policy the tree was laid out under.
    def mask : String
      told = @mask
      return told if told

      MaskedField.mask_for policy
    end

    # *preferred* where it measures a single cell under *policy*, and
    # *fallback* otherwise.
    def self.mask_for(policy : Unicode::WidthPolicy,
                      preferred : String = MASK,
                      fallback : String = ASCII_MASK) : String
      Glyphs.single_cell?({preferred}, policy) ? preferred : fallback
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      return super if @reveal

      @policy = policy
      wanted = prompt_width + Math.max(buffer.size * mask_width(policy), 1)

      Layout::Intrinsic.new prompt_width + 1, wanted
    end

    # Cells one mark takes under the policy the tree was laid out with.
    def mask_width : Int32
      mask_width @policy
    end

    # Cells one mark takes, never fewer than one: a mark of no width would
    # make a field of no width however much was typed into it.
    def mask_width(policy : Unicode::WidthPolicy) : Int32
      Math.max Unicode.string_width(mask, policy), 1
    end

    # Marks there is room for on the row.
    def masks_shown : Int32
      Math.max (content.width - prompt_width) // mask_width, 1
    end

    # Keeps the cursor in view, in marks rather than in cells.
    def reflow_mask : Nil
      room = masks_shown
      cursor = buffer.cursor

      @mask_offset = cursor if cursor < @mask_offset
      @mask_offset = cursor - room + 1 if cursor - @mask_offset >= room
      @mask_offset = Math.max @mask_offset, 0
    end

    # Where the terminal's own cursor belongs, counted in marks.
    def cursor_position : {Int32, Int32}?
      return super if @reveal

      area = content
      return if area.empty?

      right = Math.max area.width - 1, 0
      column = prompt_width + (buffer.cursor - @mask_offset) * mask_width

      {column.clamp(0, right), 0}
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return super if @reveal
      return if view.width <= 0 || view.height <= 0

      draw_mask view
      draw_error view
    end

    private def draw_mask(view : View) : Nil
      draw_prompt view, 0, first: true
      left = prompt_width
      room = Math.max view.width - left, 0
      return if room.zero?
      return draw_placeholder view, left, 0, room if buffer.empty?

      reflow_mask
      write_marks view, left
    end

    private def write_marks(view : View, left : Int32) : Nil
      mark = mask
      cells = mask_width view.policy
      room = masks_shown
      last = Math.min buffer.size, @mask_offset + room
      shown = last - @mask_offset
      return if shown <= 0

      view.write left, 0, mark * shown
      return unless buffer.size > last

      # A mark of the row's own at the right edge, so that what is off it is
      # visible rather than merely absent.
      view.write_char left + (shown - 1) * cells, 0, Field::MARKERS[1], Style::DEFAULT.faint
    end
  end
end
