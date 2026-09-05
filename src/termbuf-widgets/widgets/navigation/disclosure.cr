require "../../message"
require "../../router"
require "../../widget"
require "../panel"
require "../input/interactive"

module TermBuf::Widgets
  # A header that opens and closes what is under it.
  #
  #     section = Disclosure.new "advanced"
  #     section.body.add checkbox, field
  #     section.expanded = true
  #
  # `Enter`, `Space` and a click on the header turn it over, and each of those
  # says `Toggled`. What is under it is an ordinary `Panel`, reached through
  # `#body`, so anything at all can go in one.
  #
  # `#expanded` is a `layout_property` because what is under the header is
  # geometry: closing a section takes its body out of the layout entirely
  # rather than drawing it somewhere out of sight, so a closed section costs
  # one row whatever is in it.
  class Disclosure < Widget
    # A section was opened or closed.
    struct Toggled < Message
      # Which section it was, since one handler usually answers several.
      getter disclosure : Disclosure

      # Whether it is now open.
      getter? expanded : Bool

      def initialize(@disclosure : Disclosure, @expanded : Bool)
      end
    end

    # The header row: the expander and the title.
    #
    # It is a widget of its own because it is the part that takes the keyboard
    # and answers a click, and because a section that is closed still has to
    # have something in the tab order.
    class Header < Widget
      include Interactive

      # The two expanders on a terminal that measures them at one cell, open
      # first.
      GLYPHS = {"▼", "▶"}

      # What stands in for them where they do not come out at one cell each.
      GLYPHS_ASCII = {"-", "+"}

      # The keys that turn a section over while its header has the keyboard.
      TOGGLE_KEYS = {"Enter", "Space"}

      # What the header says.
      layout_property title : String = ""

      # What it is drawn in while it does not have the keyboard.
      property normal_style : Style = Style::DEFAULT

      # What it is drawn in while it does.
      property focused_style : Style = Style::DEFAULT.reverse

      def initialize(@title : String = "", style : Style? = nil)
        @style = style
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.fit
        self.keymap = toggling
      end

      # The section this header belongs to, or `nil` for one not in a tree.
      def disclosure? : Disclosure?
        parent.as? Disclosure
      end

      # Whether the section is open, which is what picks the expander.
      def expanded? : Bool
        held = disclosure?
        held ? held.expanded? : false
      end

      # Focus lands on the header, which is the part that opens and closes.
      def focusable? : Bool
        true
      end

      # The expander this header draws under *policy*.
      def glyph(policy : Unicode::WidthPolicy) : String
        open, closed = Glyphs.single_cell?(GLYPHS, policy) ? GLYPHS : GLYPHS_ASCII
        expanded? ? open : closed
      end

      # What the whole row reads as under *policy*.
      def text(policy : Unicode::WidthPolicy) : String
        "#{glyph policy} #{@title}"
      end

      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse

        clicked event, context do
          take_focus context
          disclosure?.try &.toggle
        end
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        wanted = Unicode.string_width text(policy), policy
        Layout::Intrinsic.new Math.min(wanted, 2), wanted
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        1
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        paint = focused? ? @focused_style : @normal_style
        view.write 0, 0, Unicode.truncate(text(view.policy), view.width, view.policy), paint
      end

      private def toggling : Bindings
        Bindings.build do |map|
          TOGGLE_KEYS.each do |key|
            map.bind Key.parse(key), "open or close this section",
              ->(_context : Context) { disclosure?.try &.toggle; nil }
          end
        end
      end
    end

    # Whether what is under the header is showing.
    layout_property? expanded : Bool = false

    # The header row, which is this widget's first child.
    getter header : Header

    # What is under it, which is its second. Put the section's content in
    # here.
    getter body : Panel

    def initialize(title : String = "",
                   expanded : Bool = false,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   indent : Int32 = 2,
                   style : Style? = nil)
      @expanded = expanded
      @direction = Layout::Direction::Column
      @width = width
      @height = height
      @style = style
      @header = Header.new title
      @body = Panel.new width: Layout::Sizing.grow, height: Layout::Sizing.fit,
        padding: Layout::Padding.new(0, 0, 0, indent)
      @body.hidden = !expanded
      add @header
      add @body
    end

    # What the header says.
    def title : String
      @header.title
    end

    # :ditto:
    def title=(title : String) : String
      @header.title = title
    end

    # Opens or closes the section, taking the body in and out of the layout.
    def expanded=(value : Bool) : Bool
      result = previous_def
      @body.hidden = !value
      result
    end

    # Turns the section over and says `Toggled`.
    #
    # This is the verb: a key and a click both come through here, so this is
    # where the message belongs. Setting `#expanded` says nothing.
    def toggle : Nil
      self.expanded = !@expanded
      emit Toggled.new self, @expanded
    end
  end

  # A set of `Disclosure` sections, optionally an accordion.
  #
  #     group = DisclosureGroup.new exclusive: true
  #     group.add "general"
  #     group.add "advanced"
  #
  # An exclusive group closes whichever section was open when another is
  # opened, which is what makes it an accordion. Closing the sections that were
  # not the one the user acted on says nothing: one action, one message.
  class DisclosureGroup < Widget
    # Whether opening one section closes the others.
    property? exclusive : Bool

    def initialize(@exclusive : Bool = false,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.fit,
                   gap : Int32 = 0,
                   style : Style? = nil)
      @direction = Layout::Direction::Column
      @width = width
      @height = height
      @gap = gap
      @style = style
    end

    # The sections in the group, in the order they were added.
    def sections : Array(Disclosure)
      @children.compact_map &.as?(Disclosure)
    end

    # Adds a section and answers it.
    def add(title : String, expanded : Bool = false) : Disclosure
      section = Disclosure.new title, expanded
      add section
      section
    end

    # The section that is open, or `nil` when none is. An exclusive group has
    # at most one.
    def open_section : Disclosure?
      sections.find &.expanded?
    end

    # Closes every section but the one that was just opened.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Disclosure::Toggled
      return unless @exclusive && event.expanded?

      sections.each do |section|
        section.expanded = false unless section.same? event.disclosure
      end
    end
  end
end
