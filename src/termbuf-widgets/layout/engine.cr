require "../widget"
require "./sizing"
require "./tree"

module TermBuf::Widgets::Layout
  # One share in an apportionment: how much of the weight it claims, and the
  # bounds the result has to land inside.
  record Slot, weight : Int32, min : Int32 = 0, max : Int32 = Int32::MAX do
    # The ceiling, never below the floor. A widget whose content outgrew a
    # `Sizing` it cannot meet has a minimum above its maximum, and the floor
    # is the one that has to hold.
    def ceiling : Int32
      Math.max @max, @min
    end
  end

  # Which of the two axes a pass is working on.
  enum Axis
    # Columns.
    X

    # Rows.
    Y
  end

  # The layout algorithm: a reimplementation, in whole cells, of the one in
  # Clay (https://github.com/nicbarker/clay).
  #
  # Six passes over the tree, each of which has to finish before the next can
  # start:
  #
  # 1. `fit_widths` bottom up. A leaf takes its `Widget#intrinsic_width`, a
  #    row the sum of its children plus gaps and inset, a column the widest of
  #    them. `Sizing::Mode::Grow` and `Percent` count as nothing here, because
  #    what they get is not known until their parent's width is.
  # 2. `distribute_widths` top down. Percent children take their share of the
  #    content box, then what is left over is either grown into or, when it is
  #    negative, shrunk out of the `Fit` and `Grow` children.
  # 3. `wrap_text`: every leaf now knows how wide it is, so it can say how
  #    tall it turns out to be.
  # 4. `fit_heights`, as 1.
  # 5. `distribute_heights`, as 2.
  # 6. `position` top down, laying the children out along the axis from the
  #    content origin and aligning what is left over.
  #
  # Two deliberate differences from Clay: a border consumes cells rather than
  # being drawn over them, and shrinking is proportional rather than taking
  # from the largest child first, so a row compressed by one column loses it
  # from wherever the rounding puts it rather than from whichever child
  # happens to be widest.
  module Engine
    extend self

    # Lays *tree* out. Every widget under the root comes back with a `#rect`.
    def run(tree : Tree) : Nil
      root = tree.root
      policy = tree.policy
      screen = tree.screen

      fit root, policy, Axis::X
      root.rect = Rect.new screen.x, screen.y, screen.width, root.rect.height
      distribute root, Axis::X

      wrap_text root, policy

      fit root, policy, Axis::Y
      root.rect = Rect.new screen.x, screen.y, screen.width, screen.height
      distribute root, Axis::Y

      position root
    end

    # Divides *total* among *slots* in proportion to their weights, keeping
    # every result inside its own bounds and the sum exact.
    #
    # The shares are read off boundaries rather than rounded one at a time:
    # slot *i* runs from `(weight(0..i - 1) * total + half) / weight_sum` to
    # the same expression one slot further along, so the rounding error never
    # accumulates and the boundaries always reach *total* exactly.
    #
    # A slot that lands outside `[min, max]` is fixed at the bound it broke,
    # taken out of *total* and out of the weight, and the rest are divided
    # again. Each round pins at least one slot, so this ends in at most
    # `slots.size` rounds.
    #
    # *total_weight* is the denominator to divide against, which is the sum of
    # the weights for grow and shrink and a flat 100 for percent, where the
    # shares are of the whole box whether or not they add up to it.
    def apportion(slots : Array(Slot), total : Int32, total_weight : Int32? = nil) : Array(Int32)
      results = Array(Int32).new slots.size, 0
      return results if slots.empty?

      weight = (total_weight || slots.sum(&.weight)).to_i64
      budget = total.to_i64
      open = (0...slots.size).to_a

      slots.size.times do
        break if open.empty?

        share open, slots, results, budget, weight
        clamped = false

        open.reject! do |index|
          slot = slots[index]
          value = results[index]
          bound = if value < slot.min
                    slot.min
                  elsif value > slot.ceiling
                    slot.ceiling
                  end
          next false unless bound

          results[index] = bound
          budget -= bound
          weight -= slot.weight
          clamped = true
        end

        break unless clamped
      end

      results
    end

    # Writes each open slot's share of *budget* into *results*.
    private def share(open : Array(Int32), slots : Array(Slot), results : Array(Int32),
                      budget : Int64, weight : Int64) : Nil
      if weight <= 0
        open.each { |index| results[index] = 0 }
        return
      end

      cumulative = 0_i64
      previous = 0_i64
      half = weight // 2

      open.each do |index|
        cumulative += slots[index].weight
        boundary = (cumulative * budget + half) // weight
        results[index] = (boundary - previous).to_i32
        previous = boundary
      end
    end

    # Pass 1 and 4: what each widget would be at, bottom up.
    private def fit(widget : Widget, policy : Unicode::WidthPolicy, axis : Axis) : Nil
      if widget.hidden?
        set_size widget, axis, 0
        set_min widget, axis, 0
        return
      end

      widget.children.each { |child| fit child, policy, axis }

      extent = widget.leaf? ? leaf_extent(widget, policy, axis) : content_extent(widget, axis)
      sizing = sizing_of widget, axis
      spacing = inset_along widget, axis

      set_min widget, axis, sizing.clamp(extent.min + spacing)
      set_size widget, axis, case sizing.mode
      in .fixed?           then sizing.min
      in .fit?             then sizing.clamp(extent.preferred + spacing)
      in .grow?, .percent? then 0
      end
    end

    # What a leaf asks for, which on the vertical axis is whatever
    # `wrap_text` already worked out.
    #
    # There is no measured floor on the vertical axis the way
    # `Widget#intrinsic_width` is one on the horizontal: nothing asks a widget
    # how few rows it could survive in. The floor is therefore whatever its
    # `Sizing` declares, so a panel that must keep a row says
    # `Sizing.fit(min: 1)` and a column with more content than height
    # compresses the rest.
    private def leaf_extent(widget : Widget, policy : Unicode::WidthPolicy, axis : Axis) : Intrinsic
      case axis
      in .x? then widget.intrinsic_width policy
      in .y? then Intrinsic.new 0, widget.rect.height
      end
    end

    # What a widget's children add up to: laid end to end along the axis they
    # stack on, and the largest of them across it.
    private def content_extent(widget : Widget, axis : Axis) : Intrinsic
      children = widget.visible_children
      return Intrinsic.new 0, 0 if children.empty?

      if along_axis? widget, axis
        gaps = gap_total widget, children.size
        minimum = children.sum { |child| min_of child, axis }
        preferred = children.sum { |child| size_of child, axis }
        Intrinsic.new minimum + gaps, preferred + gaps
      else
        minimum = children.max_of { |child| min_of child, axis }
        preferred = children.max_of { |child| size_of child, axis }
        Intrinsic.new minimum, preferred
      end
    end

    # Pass 2 and 5: hand each widget's content box out to its children, top
    # down.
    private def distribute(widget : Widget, axis : Axis) : Nil
      return if widget.hidden?

      children = widget.visible_children
      unless children.empty?
        content = Math.max 0, size_of(widget, axis) - inset_along(widget, axis)
        if along_axis? widget, axis
          distribute_along widget, children, content, axis
        else
          distribute_across children, content, axis
        end
      end

      widget.children.each { |child| distribute child, axis }
    end

    # Along the stacking axis, where the children share one run of cells.
    private def distribute_along(widget : Widget, children : Array(Widget),
                                 content : Int32, axis : Axis) : Nil
      base = Math.max 0, content - gap_total(widget, children.size)

      apply_percent children, base, axis

      remaining = base - children.sum { |child| size_of child, axis }
      return if remaining.zero?

      if remaining < 0
        # A widget that clips this axis is a window onto its content, so the
        # content keeps the size it asked for and the edges do the cutting.
        return if clips? widget, axis

        shrink children.select { |child| flexible? child, axis }, remaining, axis
      else
        grow children.select { |child| sizing_of(child, axis).grow? }, remaining, axis
      end
    end

    # Across the stacking axis, where every child gets the whole content box
    # to place itself in.
    private def distribute_across(children : Array(Widget), content : Int32, axis : Axis) : Nil
      children.each do |child|
        sizing = sizing_of child, axis
        value = case sizing.mode
                in .fixed?   then sizing.min
                in .grow?    then Math.min content, sizing.max
                in .percent? then round_share(sizing.weight, content)
                in .fit?     then size_of child, axis
                end

        # The content box is the ceiling here, not the floor: nothing overflows
        # across the stacking axis, so a child wider than its parent is cut to
        # the parent even when its own minimum says otherwise.
        set_size child, axis, Math.min(Math.max(value, min_of(child, axis)), content)
      end
    end

    # Gives every `Percent` child its share of *base*, by the same boundaries
    # the other two modes use.
    private def apply_percent(children : Array(Widget), base : Int32, axis : Axis) : Nil
      shares = children.select { |child| sizing_of(child, axis).percent? }
      return if shares.empty?

      slots = shares.map do |child|
        sizing = sizing_of child, axis
        Slot.new sizing.weight, min_of(child, axis), sizing.max
      end

      assign shares, apportion(slots, base, 100), axis
    end

    # Divides *remaining* among the growers.
    private def grow(children : Array(Widget), remaining : Int32, axis : Axis) : Nil
      return if children.empty?

      slots = children.map do |child|
        sizing = sizing_of child, axis
        Slot.new sizing.weight, min_of(child, axis), sizing.max
      end

      assign children, apportion(slots, remaining), axis
    end

    # Takes *remaining*, which is negative, out of the children that can give
    # it, in proportion to what each of them currently has.
    private def shrink(children : Array(Widget), remaining : Int32, axis : Axis) : Nil
      return if children.empty?

      sizes = children.map { |child| size_of child, axis }
      total = sizes.sum
      slots = children.map_with_index do |child, index|
        Slot.new sizes[index], min_of(child, axis), sizes[index]
      end

      assign children, apportion(slots, Math.max(0, total + remaining), total), axis
    end

    private def assign(children : Array(Widget), sizes : Array(Int32), axis : Axis) : Nil
      children.each_with_index { |child, index| set_size child, axis, sizes[index] }
    end

    # Pass 3: every leaf is as wide as it is going to get, so it can say how
    # many rows that takes.
    private def wrap_text(widget : Widget, policy : Unicode::WidthPolicy) : Nil
      return if widget.hidden?

      if widget.leaf?
        set_size widget, Axis::Y, Math.max(0, widget.height_for_width(widget.rect.width, policy))
      else
        widget.children.each { |child| wrap_text child, policy }
      end
    end

    # Pass 6: put the children where their sizes say they go.
    private def position(widget : Widget) : Nil
      children = widget.visible_children
      hide_rest widget, children

      unless children.empty?
        content = widget.content
        case widget.direction
        in .row?    then place children, widget, content, Axis::X
        in .column? then place children, widget, content, Axis::Y
        end
      end

      children.each { |child| position child }
    end

    # Lays *children* out along *axis* inside *content*, and centres or ends
    # them on the other one.
    private def place(children : Array(Widget), widget : Widget, content : Rect, axis : Axis) : Nil
      gap = widget.gap
      used = children.sum { |child| size_of child, axis } + gap_total(widget, children.size)
      leading = if children.any? { |child| sizing_of(child, axis).grow? }
                  0
                else
                  align_offset used, extent_of(content, axis), align_of(widget, axis)
                end

      cross = cross_axis axis
      cursor = origin_of(content, axis) + leading - scroll_of(widget, axis)
      base = origin_of(content, cross) - scroll_of(widget, cross)

      children.each_with_index do |child, index|
        cursor += gap unless index.zero?
        offset = align_offset size_of(child, cross), extent_of(content, cross), align_of(widget, cross)
        child.rect = build_rect cursor, base + offset, child.rect, axis
        cursor += size_of child, axis
      end
    end

    # A hidden widget takes no space and sits where its parent's content
    # starts, so nothing under it is left pointing at an old frame.
    private def hide_rest(widget : Widget, shown : Array(Widget)) : Nil
      return if shown.size == widget.children.size

      content = widget.content
      widget.children.each do |child|
        next unless child.hidden?

        child.rect = Rect.new content.x, content.y, 0, 0
      end
    end

    private def build_rect(along : Int32, across : Int32, rect : Rect, axis : Axis) : Rect
      case axis
      in .x? then Rect.new along, across, rect.width, rect.height
      in .y? then Rect.new across, along, rect.width, rect.height
      end
    end

    # Where a widget sits in space its parent did not give away.
    private def align_offset(used : Int32, available : Int32, align : Align) : Int32
      leftover = available - used
      return 0 if leftover <= 0

      case align
      in .start?  then 0
      in .center? then leftover // 2
      in .end?    then leftover
      end
    end

    # *percent* hundredths of *total*, rounded to the nearest cell.
    private def round_share(percent : Int32, total : Int32) : Int32
      (percent * total + 50) // 100
    end

    private def cross_axis(axis : Axis) : Axis
      case axis
      in .x? then Axis::Y
      in .y? then Axis::X
      end
    end

    private def along_axis?(widget : Widget, axis : Axis) : Bool
      case widget.direction
      in .row?    then axis.x?
      in .column? then axis.y?
      end
    end

    private def flexible?(widget : Widget, axis : Axis) : Bool
      sizing = sizing_of widget, axis
      sizing.fit? || sizing.grow?
    end

    private def clips?(widget : Widget, axis : Axis) : Bool
      case axis
      in .x? then widget.clip_x?
      in .y? then widget.clip_y?
      end
    end

    private def scroll_of(widget : Widget, axis : Axis) : Int32
      return 0 unless clips? widget, axis

      case axis
      in .x? then widget.scroll_x
      in .y? then widget.scroll_y
      end
    end

    private def align_of(widget : Widget, axis : Axis) : Align
      case axis
      in .x? then widget.align_x
      in .y? then widget.align_y
      end
    end

    private def sizing_of(widget : Widget, axis : Axis) : Sizing
      case axis
      in .x? then widget.width
      in .y? then widget.height
      end
    end

    private def inset_along(widget : Widget, axis : Axis) : Int32
      spacing = widget.inset
      case axis
      in .x? then spacing.horizontal
      in .y? then spacing.vertical
      end
    end

    private def gap_total(widget : Widget, count : Int32) : Int32
      count > 1 ? widget.gap * (count - 1) : 0
    end

    private def size_of(widget : Widget, axis : Axis) : Int32
      extent_of widget.rect, axis
    end

    private def extent_of(rect : Rect, axis : Axis) : Int32
      case axis
      in .x? then rect.width
      in .y? then rect.height
      end
    end

    private def origin_of(rect : Rect, axis : Axis) : Int32
      case axis
      in .x? then rect.x
      in .y? then rect.y
      end
    end

    private def set_size(widget : Widget, axis : Axis, value : Int32) : Nil
      value = Math.max 0, value
      rect = widget.rect
      widget.rect = case axis
                    in .x? then Rect.new rect.x, rect.y, value, rect.height
                    in .y? then Rect.new rect.x, rect.y, rect.width, value
                    end
    end

    private def min_of(widget : Widget, axis : Axis) : Int32
      case axis
      in .x? then widget.min_width
      in .y? then widget.min_height
      end
    end

    private def set_min(widget : Widget, axis : Axis, value : Int32) : Nil
      value = Math.max 0, value
      current = widget.min_size
      widget.min_size = case axis
                        in .x? then {value, current[1]}
                        in .y? then {current[0], value}
                        end
    end
  end
end
