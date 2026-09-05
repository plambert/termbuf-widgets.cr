# The data group: widgets that put a source of rows on the screen without
# building a widget per row.
#
# * `TermBuf::Widgets::Table` — rows in columns, with a header that stays put
#   while the rows scroll.
# * `TermBuf::Widgets::DataGrid` — a table with a focused cell, in-place
#   editing through a `TermBuf::Widgets::Field`, and a sort order held beside
#   the source rather than in it.
#
# Both ask their source only for the rows that are showing, the way
# `TermBuf::Widgets::VirtualList` does, so what they cost is the size of the
# window rather than the size of the data. The exception is stated where it
# is: sorting a grid asks for every row once.

require "./data/table"
require "./data/data_grid"
