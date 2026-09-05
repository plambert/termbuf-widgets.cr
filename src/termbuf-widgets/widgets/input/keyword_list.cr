require "../../editing/completion"
require "../../message"
require "../../router"
require "../../widget"
require "../field"
require "./interactive"

module TermBuf::Widgets
  # A field for typing keywords into, and the ones already typed sitting above
  # it as chips.
  #
  #     keywords = KeywordList.new %w[crystal terminal widgets]
  #     root.add keywords
  #
  # `Enter` and `,` turn what is in the field into a chip, completing it to one
  # of the known slugs where the text names exactly one of them. `Tab`
  # completes without adding, which is `Field`'s own completion doing the work.
  #
  # ### Taking one back
  #
  # `Backspace` on an empty field selects the last chip and a second one
  # removes it, which is the two-step every tag entry uses: the first press
  # says which chip is about to go, and there is a chip highlighted on the
  # screen before anything is lost. `Left` and `Right` move that selection
  # while the field is empty, `Delete` removes the selected chip outright, and
  # a click selects one.
  #
  # ### Height
  #
  # The chips wrap, and the widget grows downward as they do. The row of them
  # is a widget of its own whose `#height_for_width` counts the wrapped rows,
  # so the height is worked out by the layout rather than set by whatever last
  # added a keyword. That is why `#keywords` is a `Widget.layout_property`: the
  # content is the geometry here, and a list mutated in place would leave the
  # tree holding last frame's rectangle.
  class KeywordList < Widget
    include Interactive

    # A keyword was added.
    struct Added < Message
      # Which list it went into.
      getter list : KeywordList

      # The slug that was added.
      getter slug : String

      def initialize(@list : KeywordList, @slug : String)
      end
    end

    # A keyword was taken back.
    struct Removed < Message
      # Which list it came out of.
      getter list : KeywordList

      # The slug that was removed.
      getter slug : String

      def initialize(@list : KeywordList, @slug : String)
      end
    end

    # The chips, wrapped across as many rows as they need.
    #
    # A leaf rather than a widget per chip: a chip is a word in a box and
    # holding a widget for each would mean a layout pass for something a single
    # walk over the strings answers. The walk is what `#height_for_width`
    # runs, and `#placements` is the same walk answering where each one went,
    # so what is drawn and what a click is tested against cannot drift apart.
    class Chips < Widget
      # Where one chip sits in the box, in cells from its top left.
      record Placement, index : Int32, x : Int32, y : Int32, width : Int32 do
        # Whether (*at_x*, *at_y*) falls on this chip.
        def contains?(at_x : Int32, at_y : Int32) : Bool
          at_y == @y && @x <= at_x < @x + @width
        end
      end

      # What goes around a chip.
      BRACKETS = {"[", "]"}

      # The keywords, in the order they were added.
      layout_property keywords : Array(String) = [] of String

      # Cells between one chip and the next.
      layout_property gap_cells : Int32 = 1

      # Which chip is picked out, or `nil` for none. Styling only, so it costs
      # no layout.
      property selected : Int32? = nil

      # What a chip is drawn in.
      property chip_style : Style = Style::DEFAULT

      # What the selected chip is drawn in.
      property selected_style : Style = Style::DEFAULT.reverse

      # How clusters are measured, taken from the tree at every layout.
      getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

      def initialize(keywords : Array(String) = [] of String)
        @keywords = keywords
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.fit
      end

      # What one chip reads as.
      def text_of(keyword : String) : String
        "#{BRACKETS[0]}#{keyword}#{BRACKETS[1]}"
      end

      # Where every chip goes in a box *width* cells across.
      def placements(width : Int32, policy : Unicode::WidthPolicy) : Array(Placement)
        placed = [] of Placement
        return placed if @keywords.empty? || width <= 0

        column = 0
        row = 0

        @keywords.each_with_index do |keyword, index|
          cells = Unicode.string_width text_of(keyword), policy

          if column > 0 && column + cells > width
            column = 0
            row += 1
          end

          placed << Placement.new(index, column, row, cells)
          column += cells + @gap_cells
        end

        placed
      end

      # Which chip (*at_x*, *at_y*) falls on, in this widget's own
      # coordinates, or `nil` for a point on none of them.
      def chip_at(at_x : Int32, at_y : Int32) : Int32?
        found = placements(content.width, @policy).find &.contains?(at_x, at_y)
        found.try &.index
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        @policy = policy
        return Layout::Intrinsic.new 0, 0 if @keywords.empty?

        widths = @keywords.map { |keyword| Unicode.string_width text_of(keyword), policy }

        Layout::Intrinsic.new widths.max,
          widths.sum + @gap_cells * (widths.size - 1)
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        @policy = policy
        placed = placements width, policy
        last = placed.last?
        last ? last.y + 1 : 0
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        picked = @selected

        placements(view.width, view.policy).each do |placement|
          break if placement.y >= view.height

          text = text_of @keywords[placement.index]
          view.write placement.x, placement.y, text,
            placement.index == picked ? @selected_style : @chip_style
        end
      end
    end

    # The chips, which are this list's first child.
    getter chips : Chips

    # The field the keywords are typed into.
    getter field : Field

    # The slugs the field completes to.
    property slugs : Array(String)

    def initialize(slugs : Array(String) = [] of String,
                   keywords : Array(String) = [] of String,
                   prompt : Field::Prompt? = nil,
                   placeholder : String? = nil,
                   border : Border? = nil,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @slugs = slugs
      @width = width
      @height = Layout::Sizing.fit
      @style = style
      @direction = Layout::Direction::Column

      @chips = Chips.new keywords
      @field = Field.new prompt: prompt, placeholder: placeholder, border: border
      add @chips, @field

      @field.completions = ->(request : Completion::Request) : Completion::Result do
        Completion::Result.new matching(request.word)
      end

      self.keymap = editing
    end

    # ------------------------------------------------------ the keywords

    # The keywords, in the order they were added.
    def keywords : Array(String)
      @chips.keywords
    end

    # Sets them outright. Says nothing: a message is what the user did, and
    # this is the application saying what the state is.
    def keywords=(wanted : Array(String)) : Array(String)
      @chips.selected = nil
      @chips.keywords = wanted
    end

    # Which chip is picked out, or `nil` for none.
    def selected : Int32?
      @chips.selected
    end

    # Picks out the chip at *index*, or none for `nil`.
    def selected=(index : Int32?) : Int32?
      index = nil if index && !(0 <= index < keywords.size)
      @chips.selected = index
    end

    # Adds *slug*, unless it is already there, and says so.
    def add_keyword(slug : String) : Bool
      return false if slug.blank? || keywords.includes?(slug)

      @chips.keywords = keywords.dup << slug
      emit Added.new self, slug
      true
    end

    # Takes the keyword at *index* out and says so.
    def remove_keyword(index : Int32) : String?
      wanted = keywords[index]?
      return unless wanted

      left = keywords.dup
      left.delete_at index
      @chips.keywords = left
      self.selected = index < left.size ? index : left.size - 1
      emit Removed.new self, wanted
      wanted
    end

    # Turns what is in the field into a chip, completing it where the text
    # names exactly one slug.
    def add_typed : Nil
      wanted = @field.text.strip
      return if wanted.empty?

      @field.text = ""
      self.selected = nil
      add_keyword completion_for(wanted)
    end

    # The slug *text* stands for: itself when it is one, the only slug it
    # begins when there is exactly one, and the text as typed otherwise.
    def completion_for(text : String) : String
      return text if @slugs.includes? text

      found = matching text
      found.size == 1 ? found.first : text
    end

    # The slugs beginning with *word*.
    def matching(word : String) : Array(String)
      return @slugs.dup if word.empty?

      @slugs.select &.starts_with?(word)
    end

    # ------------------------------------------------------------- events

    # `Backspace` on an empty field: the last chip, then that chip gone.
    def rub_out : Nil
      return @field.press(Key.named(Key::Name::Backspace)) unless @field.text.empty?

      picked = selected
      return remove_keyword picked if picked

      self.selected = keywords.size - 1 unless keywords.empty?
    end

    # `Delete`: the selected chip, or the character after the cursor.
    def cut : Nil
      picked = selected
      return remove_keyword picked if picked

      @field.press Key.named(Key::Name::Delete)
    end

    # Moves the chip selection *step* places while the field is empty, and
    # moves the cursor otherwise.
    #
    # Stepping past the last chip lets the selection go, which puts the
    # keyboard back on the text: the chips sit before the field, so walking
    # off the end of them is walking into it. Stepping past the first stays
    # where it is, because there is nothing on that side to walk into.
    def step(step : Int32) : Nil
      unless @field.text.empty?
        return @field.press Key.named(step < 0 ? Key::Name::Left : Key::Name::Right)
      end

      return if keywords.empty?

      picked = selected
      unless picked
        self.selected = keywords.size - 1 if step < 0
        return
      end

      wanted = picked + step
      return if wanted < 0

      self.selected = wanted < keywords.size ? wanted : nil
    end

    # A click picks out the chip it landed on and puts the keyboard back in
    # the field.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      clicked event, context do
        box = @chips.content
        index = @chips.chip_at event.x - box.x, event.y - box.y
        next unless index

        self.selected = index
        context.focus.focus @field
      end
    end

    private def editing : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Enter"), "add this keyword", ->(_context : Context) { add_typed }
        map.bind Key.character(','), "add this keyword", ->(_context : Context) { add_typed }
        map.bind Key.parse("Backspace"), "rub out", ->(_context : Context) { rub_out }
        map.bind Key.parse("Delete"), "cut", ->(_context : Context) { cut }
        map.bind Key.parse("Left"), "the chip before", ->(_context : Context) { step(-1) }
        map.bind Key.parse("Right"), "the chip after", ->(_context : Context) { step 1 }
      end
    end
  end
end
