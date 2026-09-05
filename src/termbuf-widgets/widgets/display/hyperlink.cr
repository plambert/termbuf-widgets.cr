require "../../message"
require "../../widget"
require "../input/interactive"
require "../navigation/links"
require "./attached"
require "./readout"

module TermBuf::Widgets
  # A run of text that points somewhere, and says where when you look at it.
  #
  #     link = Hyperlink.new "the protocol", "https://example.com/osc8"
  #     link.attach app
  #
  # The cells carry an OSC 8 hyperlink, interned through `Linking`, so a
  # terminal that supports them makes the text clickable itself. `Enter`,
  # `Space` and a click emit `Activated`, which is what an application that
  # wants to open the URL in a browser answers. `#copy_key`, `c` unless
  # something says otherwise, puts the URL on the clipboard through
  # `App#copy` and emits `Copied`.
  #
  # Named `Hyperlink` rather than `Link` because `TermBuf::Link` is the thing
  # a `TermBuf::Style` carries: a widget of that name would hide it from every
  # other widget in this namespace.
  #
  # ### Showing the URL
  #
  # `#reveal` says where the whole URL appears while the link has the keyboard
  # or is `#selected?`: nowhere, after the text, or on a second row under it.
  #
  # The room it takes is reserved whether or not it is showing. Moving the
  # keyboard is not a layout invalidation — nothing in the tree's geometry
  # depends on where focus is — so a link that grew when it was tabbed to would
  # draw into a box laid out for the smaller one, and a second row would simply
  # be clipped away. Reserving it costs a row, or the width of the URL, and
  # keeps the rows around it from jumping as the keyboard goes past. The
  # reserved width is the *preferred* width only: a link in a box too narrow
  # for its URL is cut like anything else.
  class Hyperlink < Widget
    include Interactive
    include Copyable

    # The link was followed, by the keyboard or by a click.
    struct Activated < Message
      # Which link it was.
      getter link : Hyperlink

      # Where it points.
      getter url : String

      def initialize(@link : Hyperlink, @url : String)
      end
    end

    # The URL was put on the clipboard.
    struct Copied < Message
      # Which link it was.
      getter link : Hyperlink

      # What was copied.
      getter url : String

      def initialize(@link : Hyperlink, @url : String)
      end
    end

    # Where the whole URL appears while the link is being looked at.
    enum Reveal
      # Nowhere. The text is all there is, and the terminal's own hyperlink is
      # what says where it goes.
      None

      # After the text, with `#reveal_separator` between them.
      Suffix

      # On a second row under the text.
      Below
    end

    # The keys that follow a link while it has the keyboard.
    FOLLOW_KEYS = {"Enter", "Space"}

    # The key that copies the URL when nothing says otherwise.
    DEFAULT_COPY_KEY = "c"

    # What the link says.
    layout_property text : String = ""

    # Where it points. Empty for a link that points nowhere, which is drawn as
    # plain text and follows nothing.
    layout_property url : String = ""

    # Where the whole URL appears while the link is being looked at.
    layout_property reveal : Reveal = Reveal::Below

    # What sits between the text and the URL under `Reveal::Suffix`.
    layout_property reveal_separator : String = " "

    # Which side of the box the rows sit on when there is room to spare.
    layout_property align : Unicode::Align = Unicode::Align::Left

    # What marks a row cut short, or `nil` to cut it unmarked.
    layout_property ellipsis : String? = "…"

    # Whether this is the chosen one of a set. Styling and the reveal only;
    # whatever holds the set is what keeps it true of one at a time.
    property? selected : Bool = false

    # What the text is drawn in when nothing else applies.
    property normal_style : Style = Style::DEFAULT.underlined

    # What it is drawn in while it has the keyboard.
    property focused_style : Style = Style::DEFAULT.underlined.reverse

    # What the revealed URL is drawn in.
    property url_style : Style = Style::DEFAULT.faint

    @copy_key : Key

    def initialize(@text : String = "",
                   @url : String = "",
                   reveal : Reveal = Reveal::Below,
                   copy_key : Key? = nil,
                   align : Unicode::Align = Unicode::Align::Left,
                   style : Style? = nil)
      @reveal = reveal
      @align = align
      @style = style
      @copy_key = copy_key || Key.parse(DEFAULT_COPY_KEY).first
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fit
      self.keymap = bindings
    end

    # The key that copies the URL.
    def copy_key : Key
      @copy_key
    end

    # Puts the copy on a different key.
    def copy_key=(key : Key) : Key
      @copy_key = key
      self.keymap = bindings
      key
    end

    # Whether the URL is being shown, which is while the link has the keyboard
    # or is one of a set and is the chosen one.
    def revealing? : Bool
      !@reveal.none? && !@url.empty? && (focused? || @selected)
    end

    # Focus lands here on any link, including one pointing nowhere: the copy
    # key still has something to be pressed on.
    def focusable? : Bool
      true
    end

    # ------------------------------------------------------------- events

    # Says the link was followed. Does nothing for one pointing nowhere.
    def activate : Nil
      return if @url.empty?

      emit Activated.new self, @url
    end

    # Puts the URL on the clipboard, answering whether anything took it.
    def copy_url : Bool
      return false if @url.empty?
      return false unless copy @url

      emit Copied.new self, @url
      true
    end

    # A click follows the link, the way a click on a button presses it.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      clicked event, context do
        take_focus context
        activate
      end
    end

    # ------------------------------------------------------------- layout

    # The text and the URL together, which is what `Reveal::Suffix` draws.
    def suffixed : String
      "#{@text}#{@reveal_separator}#{@url}"
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      label = Unicode.string_width @text, policy
      wanted = case @reveal
               in .none?   then label
               in .suffix? then Unicode.string_width suffixed, policy
               in .below?  then Math.max(label, Unicode.string_width(@url, policy))
               end

      Layout::Intrinsic.new Math.min(wanted, 1), wanted
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @reveal.below? ? 2 : 1
    end

    # ------------------------------------------------------------ drawing

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      linked = link_style view, focused? ? @focused_style : @normal_style
      showing = revealing?

      if showing && @reveal.suffix?
        Readout.line view, 0, suffixed, @align, @ellipsis, linked
        return
      end

      Readout.line view, 0, @text, @align, @ellipsis, linked
      return unless showing && @reveal.below?

      Readout.line view, 1, @url, @align, @ellipsis, link_style(view, @url_style)
    end

    # *style* carrying this link's URL, or *style* as it stands for a link
    # pointing nowhere.
    private def link_style(view : View, style : Style) : Style
      return style if @url.empty?

      style.linked Linking.link_id(view, @url)
    end

    # The keys a link answers.
    private def bindings : Bindings
      Bindings.build do |map|
        FOLLOW_KEYS.each do |key|
          map.bind Key.parse(key), "follow the link",
            ->(_context : Context) { activate; nil }
        end

        map.bind @copy_key, "copy the address",
          ->(_context : Context) { copy_url; nil }
      end
    end
  end
end
