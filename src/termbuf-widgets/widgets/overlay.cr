# The overlay group: the widgets drawn over the screen rather than beside it.
#
# * `TermBuf::Widgets::Dialog` — a centred box with a title, a body and a row
#   of actions, modal with a backdrop by default.
# * `TermBuf::Widgets::Popover` — a box hanging off another widget, which
#   flips to the other side of its target rather than going off the screen.
# * `TermBuf::Widgets::DropdownMenu` — a popover holding a list of items.
# * `TermBuf::Widgets::Drawer` — a panel against one edge of the screen.
# * `TermBuf::Widgets::Toast` and the `TermBuf::Widgets::Toasts` that owns
#   them — a stack of short messages in a corner.
# * `TermBuf::Widgets::HelpOverlay` — a dialog listing the bindings the
#   keyboard's own chain would answer.
#
# Each is a float put up with `TermBuf::Widgets::Overlay#open` and taken down
# with `#close`, and each takes an `TermBuf::Widgets::Overlay::Catcher` one z
# below it that answers every point the overlay did not, so a click cannot
# reach what is behind it. A modal overlay pushes a focus scope with itself as
# the root. One asked for a backdrop dims what is behind it without drawing
# anything there; see `TermBuf::Widgets::Overlay#backdrop_wash`.

require "./overlay/overlay"
require "./overlay/dialog"
require "./overlay/popover"
require "./overlay/dropdown_menu"
require "./overlay/drawer"
require "./overlay/toast"
require "./overlay/help_overlay"
