require "../../widget"
require "./attached"

module TermBuf::Widgets
  # A frame of an animation that says something is still going on, with an
  # optional word beside it.
  #
  #     spinner = Spinner.new "loading"
  #     spinner.start app
  #     spinner.stop
  #
  # The frame changes on a timer the application lends it. Nothing here opens a
  # clock: `#start` arms one through `App#after` and arms the next from inside
  # the last, so a spinner on an application that wired no clock in simply
  # stays on its first frame. See `Ticking`.
  #
  # ### The width never moves
  #
  # Every frame is drawn in the same number of cells — the widest frame in the
  # set under the tree's width policy — and the narrower ones are padded out to
  # it. That is what lets `#index=` skip `Widget#invalidate_layout` altogether:
  # a spinner turning at twelve frames a second that invalidated the layout on
  # every one would lay the tree out twelve times a second for an animation
  # that never changes size.
  #
  # ### Glyphs
  #
  # `#frames` is the set to draw, and `#fallback` the set to use instead when
  # the first does not come out at a cell per frame under the policy. The
  # default pair is `Frames::BRAILLE` and `Frames::ASCII`.
  #
  # Braille survives a terminal configured for CJK text, where the block
  # elements of `Frames::BAR` are drawn two cells wide, which is why it is the
  # default. A set named for both leaves the question closed:
  #
  #     spinner.frames = Spinner::Frames::BAR
  #     spinner.fallback = Spinner::Frames::BAR
  class Spinner < Widget
    include Ticking

    # How long a frame is up when nothing says otherwise.
    DEFAULT_INTERVAL = 80.milliseconds

    # The frames of one animation, in the order they are shown.
    struct Frames
      # The frames themselves.
      getter frames : Array(String)

      def initialize(frames : Enumerable(String))
        @frames = frames.to_a
        raise ArgumentError.new "a spinner needs at least one frame" if @frames.empty?
      end

      # How many there are.
      def size : Int32
        @frames.size
      end

      # Frame *index*, counting round the set as many times as it takes.
      def [](index : Int32) : String
        @frames[index % @frames.size]
      end

      # The widest frame under *policy*, which is the room a spinner reserves
      # for every one of them.
      def width(policy : Unicode::WidthPolicy) : Int32
        @frames.max_of { |frame| Unicode.string_width frame, policy }
      end

      # Whether every frame is exactly one cell under *policy*.
      def single_cell?(policy : Unicode::WidthPolicy) : Bool
        @frames.all? { |frame| Unicode.string_width(frame, policy) == 1 }
      end

      # The braille dots, which are one cell wide under every policy this
      # shard knows how to build.
      BRAILLE = new %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]

      # A block growing and shrinking. East Asian Ambiguous, so a terminal
      # configured for CJK text draws these two cells wide.
      BAR = new %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ ▆ ▅ ▄ ▃ ▂]

      # A gap running round a circle.
      ARC = new %w[◜ ◠ ◝ ◞ ◡ ◟]

      # The moon, which is Ambiguous and comes out ragged under a CJK policy:
      # some of its phases widen and some do not.
      MOON = new %w[◐ ◓ ◑ ◒]

      # The oldest one there is, and the fallback for all of the above.
      ASCII = new ["|", "/", "-", "\\"]
    end

    # The set to draw, when the policy allows it.
    layout_property frames : Frames = Frames::BRAILLE

    # The set to draw instead when `#frames` would not come out at a cell each.
    layout_property fallback : Frames = Frames::ASCII

    # What is written after the frame, or empty for a spinner on its own.
    layout_property text : String = ""

    # What sits between the frame and the text. Only drawn when there is text.
    layout_property separator : String = " "

    # How long each frame is up.
    property interval : Time::Span = DEFAULT_INTERVAL

    # What the frame is drawn in.
    property frame_style : Style = Style::DEFAULT

    # What the text beside it is drawn in.
    property text_style : Style = Style::DEFAULT

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    @index : Int32 = 0

    def initialize(text : String = "",
                   frames : Frames = Frames::BRAILLE,
                   fallback : Frames = Frames::ASCII,
                   interval : Time::Span = DEFAULT_INTERVAL,
                   separator : String = " ",
                   frame_style : Style = Style::DEFAULT,
                   text_style : Style = Style::DEFAULT,
                   style : Style? = nil)
      @text = text
      @frames = frames
      @fallback = fallback
      @interval = interval
      @separator = separator
      @frame_style = frame_style
      @text_style = text_style
      @style = style
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
    end

    # Which frame is up, counting from zero.
    def index : Int32
      @index
    end

    # Puts a different frame up.
    #
    # No invalidation: every frame is drawn in the same number of cells, so
    # nothing about the layout turns on which one it is. See the class docs.
    def index=(index : Int32) : Int32
      @index = index % frames_for.size
    end

    # Moves on to the next frame.
    def advance : Nil
      self.index = @index + 1
    end

    # The set this spinner draws with under *policy*.
    def frames_for(policy : Unicode::WidthPolicy = @policy) : Frames
      @frames.single_cell?(policy) ? @frames : @fallback
    end

    # The frame that is up, under *policy*.
    #
    # Named for what it draws rather than `frame`, which `Widget` already uses
    # for the box a widget is drawn in.
    def glyph(policy : Unicode::WidthPolicy = @policy) : String
      frames_for(policy)[@index]
    end

    # Cells every frame is drawn in, the widest of the set under *policy*.
    def stride(policy : Unicode::WidthPolicy = @policy) : Int32
      frames_for(policy).width policy
    end

    # ------------------------------------------------------------- ticking

    # Moves on a frame, which is all a tick does.
    def tick : Nil
      advance
    end

    # ------------------------------------------------------------- layout

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      cells = stride policy

      unless @text.empty?
        cells += Unicode.string_width @separator, policy
        cells += Unicode.string_width @text, policy
      end

      Layout::Intrinsic.new Math.min(cells, 1), cells
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      cells = stride view.policy
      view.write 0, 0, padded(view.policy, cells), @frame_style
      return if @text.empty?

      column = cells + Unicode.string_width(@separator, view.policy)
      return if column >= view.width

      view.write column, 0, Unicode.truncate(@text, view.width - column, view.policy),
        @text_style
    end

    # The frame that is up, blanked out to *cells* so that a narrow frame
    # leaves nothing of the one before it behind.
    private def padded(policy : Unicode::WidthPolicy, cells : Int32) : String
      shown = glyph policy
      room = cells - Unicode.string_width(shown, policy)
      room > 0 ? "#{shown}#{" " * room}" : shown
    end
  end
end
