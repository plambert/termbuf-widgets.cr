require "../../message"
require "../../router"
require "../../widget"
require "../input/button"
require "../input/interactive"

module TermBuf::Widgets
  # Previous and next, and the page numbers in between.
  #
  #     pages = Pagination.new pages: 40, page: 12
  #
  # The first page, the last page and a window around the one showing are
  # always there; the runs between them are stood in for by a gap. `Left` and
  # `Right` step a page, `Home` and `End` go to either end, and a click on a
  # number goes to it. Every one of those emits `Changed`, and setting `#page`
  # from the application does not: a message says what the user did.
  #
  # Unlike the other widgets in this group, this one is built out of ordinary
  # `Button`s. There is nothing here that has to negotiate one row's width
  # across its items: which numbers are shown is settled by `#pages`, `#page`
  # and `#window` before the layout ever runs, so the buttons can be real
  # widgets that take the keyboard and answer a click on their own account.
  class Pagination < Widget
    # The page showing has changed.
    struct Changed < Message
      # Which pagination it happened on, since one handler usually answers
      # several.
      getter pagination : Pagination

      # The page now showing, counting from one.
      getter page : Int32

      def initialize(@pagination : Pagination, @page : Int32)
      end
    end

    # The mark standing in for a run of pages that is not shown.
    class Gap < Widget
      # What it is drawn with on a terminal that measures it at one cell.
      ELLIPSIS = "…"

      # What stands in for it where it does not.
      ELLIPSIS_ASCII = "..."

      def initialize(style : Style? = nil)
        @style = style
        @width = Layout::Sizing.fit
        @height = Layout::Sizing.fixed 1
        @padding = Layout::Padding.new 0, 1, 0, 1
      end

      # What the gap is drawn with under *policy*.
      def mark(policy : Unicode::WidthPolicy) : String
        Glyphs.single_cell?({ELLIPSIS}, policy) ? ELLIPSIS : ELLIPSIS_ASCII
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        Layout::Intrinsic.exact Unicode.string_width(mark(policy), policy)
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        1
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        view.write 0, 0, mark(view.policy)
      end
    end

    # What the button back a page says unless told otherwise.
    PREVIOUS_LABEL = "<"

    # :ditto: for the one forward.
    NEXT_LABEL = ">"

    # How many pages there are, at least one.
    layout_property pages : Int32 = 1

    # Which page is showing, counting from one.
    layout_property page : Int32 = 1

    # How many pages either side of the one showing are given a number of
    # their own.
    layout_property window : Int32 = 1

    # The button that goes back a page.
    getter previous : Button

    # The button that goes on a page.
    getter following : Button

    # One page's button, and the page it goes to.
    record Step, button : Button, page : Int32

    @steps = [] of Step

    def initialize(pages : Int32 = 1,
                   page : Int32 = 1,
                   window : Int32 = 1,
                   gap : Int32 = 0,
                   previous_label : String = PREVIOUS_LABEL,
                   next_label : String = NEXT_LABEL,
                   style : Style? = nil)
      @pages = Math.max pages, 1
      @page = page.clamp 1, @pages
      @window = Math.max window, 0
      @direction = Layout::Direction::Row
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fit
      @gap = gap
      @style = style
      @previous = Button.new previous_label
      @following = Button.new next_label
      rebuild
      self.keymap = stepping
    end

    # --------------------------------------------------------- the shape

    # The row as it is drawn: a page number per entry, and `nil` where a run
    # of pages is stood in for by a gap.
    #
    # The first and the last page are always there, along with `#window` pages
    # either side of the one showing. A run of exactly one page is shown rather
    # than hidden, since a gap standing in for a single number is wider than
    # the number.
    def shape : Array(Int32?)
      wanted = Set(Int32).new
      wanted << 1
      wanted << @pages
      ((@page - @window)..(@page + @window)).each do |number|
        wanted << number if 1 <= number <= @pages
      end

      spell wanted.to_a.sort!
    end

    # The numbers with the gaps put in between them.
    private def spell(numbers : Array(Int32)) : Array(Int32?)
      row = [] of Int32?
      last = 0

      numbers.each do |number|
        gap = last.zero? ? 0 : number - last

        row << (number - 1) if gap == 2
        row << nil if gap > 2

        row << number
        last = number
      end

      row
    end

    # The buttons standing for pages, each with the page it goes to.
    def steps : Array(Step)
      @steps
    end

    # The button for *number*, or `nil` when that page has no button of its
    # own.
    def button_for(number : Int32) : Button?
      @steps.find(&.page.==(number)).try &.button
    end

    # --------------------------------------------------------- the pages

    # Goes to *number*, held inside the pages there are, without saying
    # anything: a message is what the user did, and this is the application
    # saying where things stand.
    def page=(number : Int32) : Int32
      wanted = number.clamp 1, @pages
      return wanted if wanted == @page

      previous_def wanted
      rebuild
      wanted
    end

    # Sets how many pages there are, at least one, keeping `#page` inside them.
    def pages=(count : Int32) : Int32
      wanted = Math.max count, 1
      return wanted if wanted == @pages

      previous_def wanted
      @page = @page.clamp 1, wanted
      rebuild
      wanted
    end

    # Sets how many pages either side of the one showing get a number.
    def window=(width : Int32) : Int32
      wanted = Math.max width, 0
      return wanted if wanted == @window

      previous_def wanted
      rebuild
      wanted
    end

    # Goes to *number* and says `Changed` if that is a different page.
    #
    # This is the verb the keys, the buttons and an application changing pages
    # on somebody's behalf all come through.
    def go(number : Int32, context : Context? = nil) : Nil
      wanted = number.clamp 1, @pages
      return if wanted == @page

      self.page = wanted
      emit Changed.new self, wanted
      context.try { |held| focus_page held }
    end

    # Puts the keyboard on the button for the page showing, or on whichever
    # end button is still usable.
    def focus_page(context : Context) : Bool
      target = button_for(@page) || usable_end
      return false unless target

      context.focus.focus target
    end

    private def usable_end : Button?
      return @previous unless @previous.disabled?
      return @following unless @following.disabled?

      nil
    end

    # ------------------------------------------------------------ events

    # Turns a press on one of this row's buttons into a page.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Button::Pressed

      wanted = page_of event.button
      return unless wanted

      context.consume
      go wanted, context
    end

    # Which page pressing *pressed* goes to, or `nil` for a button that is not
    # one of ours.
    private def page_of(pressed : Button) : Int32?
      return @page - 1 if pressed.same? @previous
      return @page + 1 if pressed.same? @following

      @steps.find(&.button.same?(pressed)).try &.page
    end

    private def stepping : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Left"), "the page before",
          ->(context : Context) { go @page - 1, context }
        map.bind Key.parse("Right"), "the page after",
          ->(context : Context) { go @page + 1, context }
        map.bind Key.parse("Home"), "the first page",
          ->(context : Context) { go 1, context }
        map.bind Key.parse("End"), "the last page",
          ->(context : Context) { go @pages, context }
      end
    end

    # ---------------------------------------------------------- building

    # Builds the row again: the two end buttons are kept and put back, since
    # they are what `#previous` and `#following` answer and what a spec holds
    # on to, and the numbers in between are made afresh.
    private def rebuild : Nil
      clear
      @steps.clear

      add @previous
      shape.each { |entry| add_entry entry }
      add @following

      @previous.disabled = @page <= 1
      @following.disabled = @page >= @pages
    end

    private def add_entry(entry : Int32?) : Nil
      unless entry
        add Gap.new
        return
      end

      button = Button.new entry.to_s
      button.selected = entry == @page
      add button
      @steps << Step.new(button, entry)
    end
  end
end
