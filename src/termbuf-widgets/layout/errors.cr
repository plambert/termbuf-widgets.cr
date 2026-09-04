module TermBuf::Widgets::Layout
  # Anything the layout engine refuses to do.
  class Error < Exception
  end

  # A widget's geometry changed without the tree being told.
  #
  # Every layout input is reached through a setter that marks the tree dirty,
  # so a clean tree is supposed to lay out to the same rectangles it already
  # holds. `Tree.verify_invalidation = true` checks that by laying out again
  # and comparing, which turns a stale frame into this exception at the point
  # the frame would have been drawn.
  class MissedInvalidation < Error
  end
end
