require "../widget"
require "./floating"
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
      policy = tree.policy
      screen = tree.screen

      lay_out tree.root, policy, screen
      tree.floats.each { |float| lay_out_float float, tree }
    end

    # The six passes over one subtree, laid into *area*.
    #
    # The root is given the area it was handed rather than the size its own
    # `Sizing` asks for: the screen is not negotiable, and a float has had its
    # size settled by the time it gets here.
    private def lay_out(root : Widget, policy : Unicode::WidthPolicy, area : Rect) : Nil
      fit root, policy, Axis::X
      root.rect = Rect.new area.x, area.y, area.width, root.rect.height
      distribute root, Axis::X

      wrap_text root, policy

      fit root, policy, Axis::Y
      root.rect = area
      distribute root, Axis::Y

      position root
    end

    # Pass 7: one float, against whatever it is anchored to.
    #
    # A float is sized before it is placed, because where it goes depends on
    # how big it turned out to be. `Fit` and `Fixed` answer for themselves;
    # `Grow` and `Percent` have no parent box to divide, so they resolve
    # against the anchor target instead, or against the screen when there is
    # not one.
    private def lay_out_float(float : Widget, tree : Tree) : Nil
      policy = tree.policy
      screen = tree.screen
      floating = float.floating
      return unless floating

      reference = anchor_rect floating.anchor, tree
      fit float, policy, Axis::X
      width = float_extent float, Axis::X, reference.width
      float.rect = Rect.new 0, 0, width, float.rect.height
      distribute float, Axis::X

      wrap_text float, policy
      fit float, policy, Axis::Y
      height = float_extent float, Axis::Y, reference.height

      float.rect = place_float floating, reference, screen, width, height
      distribute float, Axis::Y
      position float
    end

    # What a float is placed against: its anchor target, or the screen when
    # there is no target, or when the one there is has been hidden or taken
    # out of the tree since.
    private def anchor_rect(anchor : Anchor, tree : Tree) : Rect
      target = anchor.target
      return tree.screen unless target
      return tree.screen if target.hidden? || !tree.holds? target

      target.rect
    end

    # How big a float comes out on one axis.
    private def float_extent(float : Widget, axis : Axis, reference : Int32) : Int32
      sizing = sizing_of float, axis
      value = case sizing.mode
              in .fixed?   then sizing.min
              in .fit?     then size_of float, axis
              in .grow?    then Math.min reference, sizing.max
              in .percent? then round_share sizing.weight, reference
              end

      floor = min_of float, axis
      Math.max value.clamp(floor, Math.max(sizing.max, floor)), 0
    end

    # Where a float of *width* by *height* lands.
    #
    # The two attach points are laid on top of each other and the offsets
    # applied. What happens then is the float's `Overflow`: `Flip` mirrors the
    # pair on whichever axis went off the screen and tries again, taking the
    # new position only if it is any better, and both rules finish by sliding
    # the result back inside. A float wider than the screen has nowhere to
    # slide to and sits at the left edge, where the view cuts it.
    private def place_float(floating : Floating, reference : Rect, screen : Rect,
                            width : Int32, height : Int32) : Rect
      anchor = floating.anchor
      x = attach anchor, reference, width, height, Axis::X
      y = attach anchor, reference, width, height, Axis::Y

      if floating.overflow.flip?
        x = flip anchor, reference, screen, width, height, Axis::X, x
        y = flip anchor, reference, screen, width, height, Axis::Y, y
      end

      Rect.new clamp_to(x, width, screen, Axis::X), clamp_to(y, height, screen, Axis::Y),
        width, height
    end

    # Where the float's edge falls on one axis before anything is clamped.
    private def attach(anchor : Anchor, reference : Rect, width : Int32, height : Int32,
                       axis : Axis) : Int32
      element = anchor.element.offset width, height
      parent = anchor.parent.offset reference.width, reference.height

      case axis
      in .x? then reference.x + parent[0] - element[0] + anchor.dx
      in .y? then reference.y + parent[1] - element[1] + anchor.dy
      end
    end

    # The mirrored position, when the float does not fit where it was asked to
    # go and mirroring is an improvement.
    private def flip(anchor : Anchor, reference : Rect, screen : Rect,
                     width : Int32, height : Int32, axis : Axis, at : Int32) : Int32
      size = axis.x? ? width : height
      return at if fits? at, size, screen, axis

      mirrored = attach anchor.mirror(axis), reference, width, height, axis
      fits?(mirrored, size, screen, axis) ? mirrored : at
    end

    private def fits?(at : Int32, size : Int32, screen : Rect, axis : Axis) : Bool
      start = origin_of screen, axis
      at >= start && at + size <= start + extent_of(screen, axis)
    end

    private def clamp_to(at : Int32, size : Int32, screen : Rect, axis : Axis) : Int32
      start = origin_of screen, axis
      Math.max start, Math.min(at, start + extent_of(screen, axis) - size)
    end

    # Divides *total* among *slots* in proportion to their weights, keeping
    # every result inside its own bounds and the sum exact.
    #
    # The shares are read off boundaries rather than rounded one at a time:
    # slot *i* runs from `(weight(0..i - 1) * total + half) / weight_sum` to
    # the same expression one slot further along, so the rounding error never
    # accumulates and the boundaries always reach *total* exactly.
    #
    # Bounds are settled in two rounds of that, and the order matters. First
    # the ceilings: a slot that would take more than it accepts is held there
    # and gives the rest back, which is what lets the slot beside it take what
    # was declined. Then the floors, against what the ceilings left. Doing it
    # the other way round pins a floor with cells a ceiling was about to
    # release, and the release then has nowhere to go.
    #
    # Each round pins at least one slot, so each ends in at most `slots.size`
    # passes. When the floors alone come to *total* or more, that is the answer
    # and whatever holds these slots overflows.
    def apportion(slots : Array(Slot), total : Int32) : Array(Int32)
      return Array(Int32).new(slots.size, 0) if slots.empty?
      return slots.map(&.min) if slots.sum(&.min) >= total

      results = Array(Int32).new slots.size, 0
      free = (0...slots.size).to_a
      capped = [] of Int32
      after_ceilings = settle(slots, results, free, capped, total) { |slot, value| value > slot.ceiling }
      settle(slots, results, free, [] of Int32, after_ceilings) { |slot, value| value < slot.min }

      give_back slots, results, capped, total
      results
    end

    # Each slot's own share of *total*, *whole* being what the weights are
    # shares of rather than a sum to divide up.
    #
    # This is what a percent is: 30 of 100 of the box, whether or not its
    # siblings claim the other 70, and a share held back by a bound of its own
    # moves nothing else. Boundaries again, so the shares of a whole hundred
    # come to exactly *total*.
    def share_of(slots : Array(Slot), total : Int32, whole : Int32) : Array(Int32)
      return Array(Int32).new(slots.size, 0) if whole <= 0

      cumulative = 0_i64
      previous = 0_i64
      half = (whole // 2).to_i64

      slots.map do |slot|
        cumulative += slot.weight
        boundary = (cumulative * total + half) // whole
        value = (boundary - previous).to_i32
        previous = boundary
        value.clamp slot.min, slot.ceiling
      end
    end

    # Divides *budget* among the *free* slots over and over, each pass pinning
    # every slot the block objects to at the bound it broke and taking it out
    # of the pool. Answers what is left of *budget*.
    private def settle(slots : Array(Slot), results : Array(Int32),
                       free : Array(Int32), pinned : Array(Int32), budget : Int32,
                       & : Slot, Int32 -> Bool) : Int32
      slots.size.times do
        break if free.empty?

        share free, slots, results, budget
        caught = free.select { |index| yield slots[index], results[index] }
        break if caught.empty?

        caught.each do |index|
          bound = results[index].clamp slots[index].min, slots[index].ceiling
          results[index] = bound
          budget -= bound
          free.delete index
        end
        pinned.concat caught
      end

      budget
    end

    # Hands back what the ceilings are holding when the floors turned out to
    # need it.
    #
    # A slot pinned at its ceiling was judged against a share worked out before
    # anyone's floor had been paid for. When those floors then take the box
    # past *total*, the cells to give up are the ones sitting above a floor of
    # their own, and the ceiling pins are exactly those.
    private def give_back(slots : Array(Slot), results : Array(Int32),
                          capped : Array(Int32), total : Int32) : Nil
      return if capped.empty?

      excess = results.sum - total
      return if excess <= 0

      held = capped.sum { |index| results[index] }
      group = capped.map { |index| Slot.new results[index], slots[index].min, results[index] }
      shares = apportion group, Math.max(0, held - excess)

      capped.each_with_index { |index, position| results[index] = shares[position] }
    end

    # Writes each free slot's share of *budget* into *results*.
    private def share(free : Array(Int32), slots : Array(Slot),
                      results : Array(Int32), budget : Int32) : Nil
      weight = free.sum { |index| slots[index].weight }.to_i64
      if weight <= 0
        free.each { |index| results[index] = 0 }
        return
      end

      cumulative = 0_i64
      previous = 0_i64
      half = weight // 2

      free.each do |index|
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

      # A grower has been given nothing yet, but it can never come out below
      # its own minimum, so that much of the box is already spoken for. Count
      # it, or a row whose growers insist on more than is left over never
      # notices that its fitting children could have given the room up.
      remaining = base - children.sum { |child| committed_size child, axis }

      if remaining < 0
        pin_growers children, axis

        # A widget that clips this axis is a window onto its content, so the
        # content keeps the size it asked for and the edges do the cutting.
        return if clips? widget, axis

        fitting = children.select { |child| sizing_of(child, axis).fit? }
        shrink fitting, base - total_apart_from(children, fitting, axis), axis
      else
        growers = children.select { |child| sizing_of(child, axis).grow? }
        grow growers, base - total_apart_from(children, growers, axis), axis
      end
    end

    # What a child has already laid claim to: a grower's minimum, since that
    # is the least it can end up at, and everything else's current size.
    private def committed_size(widget : Widget, axis : Axis) : Int32
      return min_of widget, axis if sizing_of(widget, axis).grow?

      size_of widget, axis
    end

    # Puts every grower at its own minimum, which is where it stays when the
    # box has nothing left over to divide.
    private def pin_growers(children : Array(Widget), axis : Axis) : Nil
      children.each do |child|
        next unless sizing_of(child, axis).grow?

        set_size child, axis, min_of(child, axis)
      end
    end

    # What the children outside *group* take up, which is what *group* has to
    # share the rest of.
    private def total_apart_from(children : Array(Widget), group : Array(Widget),
                                 axis : Axis) : Int32
      children.sum { |child| group.any?(&.same?(child)) ? 0 : size_of(child, axis) }
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

      assign shares, share_of(slots, base, 100), axis
    end

    # Divides *target* cells among the growers.
    private def grow(children : Array(Widget), target : Int32, axis : Axis) : Nil
      return if children.empty?

      slots = children.map do |child|
        sizing = sizing_of child, axis
        Slot.new sizing.weight, min_of(child, axis), sizing.max
      end

      assign children, apportion(slots, Math.max(0, target)), axis
    end

    # Fits *children* into *target* cells between them, taking the shortfall in
    # proportion to what each of them currently has and stopping at each
    # child's own minimum.
    private def shrink(children : Array(Widget), target : Int32, axis : Axis) : Nil
      return if children.empty?

      sizes = children.map { |child| size_of child, axis }
      slots = children.map_with_index do |child, index|
        Slot.new sizes[index], min_of(child, axis), sizes[index]
      end

      assign children, apportion(slots, Math.max(0, target)), axis
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

      cross = axis.other
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

    private def along_axis?(widget : Widget, axis : Axis) : Bool
      case widget.direction
      in .row?    then axis.x?
      in .column? then axis.y?
      end
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
