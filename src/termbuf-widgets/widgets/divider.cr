require "../widget"

module TermBuf::Widgets
  # A rule one cell thick, drawn across whatever room it is given.
  #
  # Which way it runs is taken from the parent it was put in: a column of
  # things is separated by rules across it, a row of them by rules down it.
  # Set `#orientation` to say so explicitly.
  #
  #     panel.add header, Divider.new(label: "details"), body
  #
  # A divider's two sizings are what make it a divider, so it answers them
  # itself: one cell thick and as long as there is room. Setting `#width` or
  # `#height` on one has no effect.
  class Divider < Widget
    # Which way the rule runs.
    enum Orientation
      # Across, one cell tall. What separates the rows of a column.
      Horizontal

      # Down, one cell wide. What separates the columns of a row.
      Vertical
    end

    # The rule a horizontal divider is drawn with unless `#glyph` says
    # otherwise.
    ACROSS = '─'

    # :ditto: for a vertical one.
    DOWN = '│'

    # Which way the rule runs, or `nil` to take it from the parent.
    layout_property orientation : Orientation? = nil

    # What the rule is drawn with, or `nil` for the one that suits the way it
    # runs.
    property glyph : Char? = nil

    # Written in the middle of a horizontal rule, or `nil` for a plain one. A
    # vertical rule has nowhere to put one and ignores it.
    layout_property label : String? = nil

    def initialize(orientation : Orientation? = nil,
                   @label : String? = nil,
                   @glyph : Char? = nil,
                   style : Style? = nil)
      @orientation = orientation
      @style = style
    end

    # Which way this rule actually runs: what it was told, or the opposite of
    # the way its parent stacks, or across when it has no parent.
    def runs : Orientation
      told = @orientation
      return told if told

      held = parent
      return Orientation::Horizontal unless held

      case held.direction
      in .column? then Orientation::Horizontal
      in .row?    then Orientation::Vertical
      end
    end

    # Whether the rule runs across rather than down.
    def horizontal? : Bool
      runs.horizontal?
    end

    # As long as there is room, and one cell thick.
    def width : Layout::Sizing
      horizontal? ? Layout::Sizing.grow : Layout::Sizing.fixed(1)
    end

    # :ditto:
    def height : Layout::Sizing
      horizontal? ? Layout::Sizing.fixed(1) : Layout::Sizing.grow
    end

    # What the rule is drawn with.
    def rule : Char
      @glyph || (horizontal? ? ACROSS : DOWN)
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      return Layout::Intrinsic.exact 1 unless horizontal?

      needed = Math.max label_width(policy), 1
      Layout::Intrinsic.new needed, needed
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      view.fill view.bounds, rule
      draw_label view
    end

    # The label with a space either side, so the rule does not run into it.
    private def labelled : String?
      text = @label
      return if text.nil? || text.empty?

      " #{text} "
    end

    private def label_width(policy : Unicode::WidthPolicy) : Int32
      text = labelled
      text ? Unicode.string_width(text, policy) : 0
    end

    private def draw_label(view : View) : Nil
      text = labelled
      return unless text && horizontal?

      shown = Unicode.truncate text, view.width, view.policy
      return if shown.empty?

      room = view.width - Unicode.string_width(shown, view.policy)
      view.write Math.max(room // 2, 0), 0, shown
    end
  end
end
