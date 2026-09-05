# The data group: widgets that put a source of rows on the screen without
# building a widget per row.
#
# * `TermBuf::Widgets::Table` — rows in columns, with a header that stays put
#   while the rows scroll.
#
# It asks its source only for the rows that are showing, the way
# `TermBuf::Widgets::VirtualList` does, so what it costs is the size of the
# window rather than the size of the data.

require "./data/table"
