require "../../widget"

module TermBuf::Widgets
  # A row of label and value pairs, the kind that sits along the bottom of an
  # application.
  #
  #     bar = StatusBar.new
  #     bar.add "branch", "main"
  #     bar.add "rows", 1_204, &.format(delimiter: '_')
  #     bar.set "rows", 1_205
  #
  # The bar is one row tall however wide it is, and grows to whatever width it
  # is given. When there is not enough room for every pair, the ones that do
  # not fit are cut from the right and the cut is marked with `#ellipsis`: the
  # leftmost pairs are the ones an application puts first, so they are the ones
  # kept.
  #
  # A value is whatever it is, turned into text by `#to_s` or by a block. The
  # block form is where a `Proc` goes, so a formatter held elsewhere is passed
  # as one:
  #
  #     rate = ->(count : Int32) { "#{count}/s" }
  #     bar.set "throughput", 90, &rate
  #
  # `#set` only invalidates the layout when the pair's width changes, because
  # only a width change can move anything. A frame is drawn from the whole
  # tree every time, so a value that stays the same width is picked up by the
  # next frame with no layout at all.
  class StatusBar < Widget
    # One pair: what it is called, what it says, and what it is drawn in.
    class Item
      # What the pair is called, and the handle `#set` and `#remove` take.
      getter label : String

      # What it says, already turned into text.
      property text : String

      # What the value is drawn in, or `nil` for the bar's own style.
      property style : Style?

      def initialize(@label : String, @text : String = "", @style : Style? = nil)
      end
    end

    # Between one pair and the next.
    layout_property separator : String = " | "

    # Between a label and its value.
    layout_property label_separator : String = ": "

    # What marks the pairs that were cut, or `nil` to cut them unmarked.
    layout_property ellipsis : String? = "…"

    # What labels are drawn in. Values take their own item's style.
    property label_style : Style = Style::DEFAULT.faint

    # The pairs, in the order they are drawn.
    getter items = [] of Item

    # How clusters are measured, taken from the tree at every layout.
    getter policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT

    def initialize(separator : String = " | ",
                   label_separator : String = ": ",
                   ellipsis : String? = "…",
                   label_style : Style = Style::DEFAULT.faint,
                   style : Style? = nil)
      @separator = separator
      @label_separator = label_separator
      @ellipsis = ellipsis
      @label_style = label_style
      @style = style
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fit
    end

    # Adds a pair at the end and returns it. *value* becomes text through
    # `#to_s`.
    def add(label : String, value = "", style : Style? = nil) : Item
      append label, value.to_s, style
    end

    # :ditto:
    #
    # The block turns *value* into text, which is where a formatter held as a
    # `Proc` is passed with `&`.
    def add(label : String, value : T, style : Style? = nil, & : T -> String) : Item forall T
      append label, yield(value), style
    end

    # Replaces the text of the pair called *label*, adding it when there is no
    # such pair, and returns it.
    def set(label : String, value) : Item
      assign label, value.to_s
    end

    # :ditto:
    def set(label : String, value : T, & : T -> String) : Item forall T
      assign label, yield(value)
    end

    # Takes the pair called *label* out, returning it, or `nil` when there was
    # no such pair.
    def remove(label : String) : Item?
      index = @items.index { |item| item.label == label }
      return unless index

      taken = @items.delete_at index
      invalidate_layout
      taken
    end

    # Takes every pair out.
    def clear_items : Nil
      return if @items.empty?

      @items.clear
      invalidate_layout
    end

    # The pair called *label*, or `nil`.
    def []?(label : String) : Item?
      @items.find { |item| item.label == label }
    end

    # What one pair reads as, label and value together.
    def text_of(item : Item) : String
      "#{item.label}#{@label_separator}#{item.text}"
    end

    # ------------------------------------------------------------- layout

    # Every pair laid end to end, with the separators between them.
    #
    # The width the bar would rather have; anything narrower costs pairs off
    # the right.
    def preferred_width(policy : Unicode::WidthPolicy = @policy) : Int32
      return 0 if @items.empty?

      gaps = (@items.size - 1) * Unicode.string_width(@separator, policy)
      @items.sum { |item| Unicode.string_width text_of(item), policy } + gaps
    end

    # The first label, which is as narrow as the bar goes before it stops
    # saying anything at all.
    def minimum_width(policy : Unicode::WidthPolicy = @policy) : Int32
      first = @items.first?
      return 0 unless first

      Math.min Unicode.string_width(first.label, policy), preferred_width(policy)
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      @policy = policy
      Layout::Intrinsic.new minimum_width(policy), preferred_width(policy)
    end

    # One row, whatever it was given.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @policy = policy
      1
    end

    # ------------------------------------------------------------ drawing

    # Draws as many pairs as fit, marking the cut when some did not.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      column = 0

      @items.each_with_index do |item, index|
        break if column >= view.width

        lead = index.zero? ? "" : @separator
        whole = lead + text_of(item)
        room = view.width - column

        if Unicode.string_width(whole, view.policy) <= room
          column = draw_pair view, column, lead, item
        else
          draw_cut view, column, whole, room, item
          break
        end
      end
    end

    # Writes one pair that fits, in three pieces so the label and the value
    # keep their own styles, and answers the column after it.
    private def draw_pair(view : View, column : Int32, lead : String, item : Item) : Int32
      unless lead.empty?
        view.write column, 0, lead, @label_style
        column += Unicode.string_width lead, view.policy
      end

      view.write column, 0, item.label, @label_style
      column += Unicode.string_width item.label, view.policy

      view.write column, 0, @label_separator, @label_style
      column += Unicode.string_width @label_separator, view.policy

      view.write column, 0, item.text, item.style || Style::DEFAULT
      column + Unicode.string_width(item.text, view.policy)
    end

    # Writes what is left of a pair too wide for the room left over.
    #
    # The pieces are not styled separately here: a cut can fall anywhere in
    # the run, including inside the label, and one write of the whole is what
    # keeps the mark at the end of it.
    private def draw_cut(view : View, column : Int32, whole : String, room : Int32,
                         item : Item) : Nil
      shown = Unicode.ellipsize whole, room, @ellipsis || "", view.policy
      return if shown.empty?

      view.write column, 0, shown, item.style || Style::DEFAULT
    end

    private def append(label : String, text : String, style : Style?) : Item
      item = Item.new label, text, style
      @items << item
      invalidate_layout
      item
    end

    # Sets a pair's text, invalidating only when that changed how wide it is.
    private def assign(label : String, text : String) : Item
      item = self[label]?
      return append label, text, nil unless item

      was = Unicode.string_width text_of(item), @policy
      item.text = text
      invalidate_layout unless was == Unicode.string_width(text_of(item), @policy)
      item
    end
  end
end
