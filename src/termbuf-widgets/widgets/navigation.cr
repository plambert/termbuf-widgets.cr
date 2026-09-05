# The navigation group: widgets that say where you are and let you go
# somewhere else.
#
# * `TermBuf::Widgets::NavigationBar` — a row of places to go, one of them
#   highlighted, collapsing to key hints and then to marks as it runs out of
#   room.
# * `TermBuf::Widgets::TabbedPanels` — a tab strip over a panel showing one
#   child at a time; the others are hidden widgets and cost no layout.

require "./navigation/links"
require "./navigation/navigation_bar"
require "./navigation/tabbed_panels"
