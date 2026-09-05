# The data group: widgets that put a source of rows on the screen without
# building a widget per row.
#
# * `TermBuf::Widgets::Table` — rows in columns, with a header that stays put
#   while the rows scroll.
# * `TermBuf::Widgets::DataGrid` — a table with a focused cell, in-place
#   editing through a `TermBuf::Widgets::Field`, and a sort order held beside
#   the source rather than in it.
# * `TermBuf::Widgets::Tree` — nodes flattened into rows, opened and closed a
#   subtree at a time, over a `TermBuf::Widgets::VirtualList`.
#
# All three ask their source only for the rows that are showing, the way the
# virtual list does, so what they cost is the size of the window rather than
# the size of the data. The two exceptions are stated where they are: sorting
# a grid asks for every row once, and flattening a tree walks whatever is
# open.

require "./data/table"
require "./data/data_grid"
require "./data/nodes"
require "./data/tree"
