# The navigation group: widgets that say where you are and let you go
# somewhere else.
#
# * `TermBuf::Widgets::NavigationBar` — a row of places to go, one of them
#   highlighted, collapsing to key hints and then to marks as it runs out of
#   room.
# * `TermBuf::Widgets::TabbedPanels` — a tab strip over a panel showing one
#   child at a time; the others are hidden widgets and cost no layout.
# * `TermBuf::Widgets::Breadcrumbs` — the path to here, each crumb clickable
#   and optionally a hyperlink, cut from the left when it will not fit.
# * `TermBuf::Widgets::Pagination` — previous and next, and the page numbers
#   in between, with a gap standing in for the runs that are not shown.
# * `TermBuf::Widgets::Disclosure` — a header that opens and closes what is
#   under it, and `TermBuf::Widgets::DisclosureGroup` to make a set of them an
#   accordion.
#
# The three that have to negotiate one row's width across several items — the
# bar, the crumbs and the tab strip — draw those items themselves rather than
# holding a widget each. Giving up a label but not the item it belongs to is a
# decision about the whole row, and the layout engine apportions space between
# children without ever asking one to spell itself differently. The two that do
# not need that — the pagination and the disclosure — are built out of ordinary
# widgets.

require "./navigation/links"
require "./navigation/navigation_bar"
require "./navigation/tabbed_panels"
require "./navigation/breadcrumbs"
require "./navigation/pagination"
require "./navigation/disclosure"
