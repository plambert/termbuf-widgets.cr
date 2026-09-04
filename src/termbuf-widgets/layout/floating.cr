require "./sizing"

module TermBuf::Widgets::Layout
  # What a floating widget does when it would land off the edge of the screen.
  enum Overflow
    # Attach to the opposite side instead, the way a menu opens upward when
    # there is no room below it, and clamp to the screen if that does not fit
    # either.
    Flip

    # Slide back until it fits, keeping the side it was attached to.
    Clamp
  end

  # One of the nine points a rectangle can be pinned by.
  #
  # A float names two: the point on itself, and the point on whatever it is
  # anchored to. The two are laid on top of each other, so a menu under a
  # button is the button's `LeftBottom` and the menu's `LeftTop`.
  enum AttachPoint
    LeftTop
    CenterTop
    RightTop
    LeftCenter
    Center
    RightCenter
    LeftBottom
    CenterBottom
    RightBottom

    # Where this point sits in a *width* by *height* rectangle, from its top
    # left. A half falls to the lower cell.
    def offset(width : Int32, height : Int32) : {Int32, Int32}
      {horizontal(width), vertical(height)}
    end

    # This point mirrored left to right.
    def mirror_x : AttachPoint
      case self
      in .left_top?      then RightTop
      in .left_center?   then RightCenter
      in .left_bottom?   then RightBottom
      in .right_top?     then LeftTop
      in .right_center?  then LeftCenter
      in .right_bottom?  then LeftBottom
      in .center_top?    then CenterTop
      in .center?        then Center
      in .center_bottom? then CenterBottom
      end
    end

    # This point mirrored top to bottom.
    def mirror_y : AttachPoint
      case self
      in .left_top?      then LeftBottom
      in .center_top?    then CenterBottom
      in .right_top?     then RightBottom
      in .left_bottom?   then LeftTop
      in .center_bottom? then CenterTop
      in .right_bottom?  then RightTop
      in .left_center?   then LeftCenter
      in .center?        then Center
      in .right_center?  then RightCenter
      end
    end

    private def horizontal(width : Int32) : Int32
      case self
      in .left_top?, .left_center?, .left_bottom?    then 0
      in .center_top?, .center?, .center_bottom?     then width // 2
      in .right_top?, .right_center?, .right_bottom? then width
      end
    end

    private def vertical(height : Int32) : Int32
      case self
      in .left_top?, .center_top?, .right_top?          then 0
      in .left_center?, .center?, .right_center?        then height // 2
      in .left_bottom?, .center_bottom?, .right_bottom? then height
      end
    end
  end

  # What a floating widget is pinned to.
  #
  # *target* is the widget it hangs off, or `nil` for the screen; a target that
  # is hidden or no longer in the tree is treated the same way. *element* is
  # the point on the float, *parent* the point on the target, and the two are
  # laid on top of each other before *dx* and *dy* shift the result.
  record Anchor,
    target : Widget? = nil,
    element : AttachPoint = AttachPoint::LeftTop,
    parent : AttachPoint = AttachPoint::LeftTop,
    dx : Int32 = 0,
    dy : Int32 = 0 do
    # This anchor pinned to *target* instead.
    def on(target : Widget?) : Anchor
      Anchor.new target, @element, @parent, @dx, @dy
    end

    # This anchor mirrored on the given axis, which is what `Overflow::Flip`
    # does to a float that will not fit.
    def mirror(axis : Axis) : Anchor
      case axis
      in .x? then Anchor.new @target, @element.mirror_x, @parent.mirror_x, -@dx, @dy
      in .y? then Anchor.new @target, @element.mirror_y, @parent.mirror_y, @dx, -@dy
      end
    end
  end

  # A widget lifted out of its parent's flow.
  #
  # It keeps its place in the widget tree, which is what makes it a child of
  # the thing it belongs to, but the layout takes no space for it and places it
  # against its `Anchor` instead. Menus, tooltips, dialogs and anything else
  # drawn over the top of the screen rather than beside it.
  record Floating,
    anchor : Anchor = Anchor.new,
    z : Int32 = 0,
    capture : Bool = true,
    overflow : Overflow = Overflow::Flip do
    # A float pinned to *target*'s *parent* corner by its own *element*
    # corner.
    def self.on(target : Widget?, element : AttachPoint = AttachPoint::LeftTop,
                parent : AttachPoint = AttachPoint::LeftTop,
                dx : Int32 = 0, dy : Int32 = 0, z : Int32 = 0,
                capture : Bool = true,
                overflow : Overflow = Overflow::Flip) : Floating
      new Anchor.new(target, element, parent, dx, dy), z, capture, overflow
    end

    # Whether a click landing on this float belongs to it rather than to
    # whatever it is covering.
    def capture? : Bool
      @capture
    end
  end
end
