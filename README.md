# termbuf-widgets

Widgets and a layout engine for [termbuf](https://github.com/plambert/termbuf.cr).

A widget is both the thing that draws and the element the layout engine sizes, so there is no
separate declaration tree to keep in step with the objects. Build a tree of widgets, hand its root
to a `Layout::Tree`, and every widget comes back carrying a rectangle in buffer coordinates that it
can draw into.

Requires Crystal 1.21 or later.

## Installation

Add the dependency to `shard.yml` and run `shards install`:

```yaml
dependencies:
  termbuf-widgets:
    github: plambert/termbuf-widgets.cr
```

That pulls in termbuf, which is the drawing side, and
[termbuf-input](https://github.com/plambert/termbuf-input.cr) behind it.

## Widgets

### Display

Widgets that show a number or a state and take no input, with the one exception of a `Rating` told
it is editable. Each is a leaf: it says how wide it wants to be, how tall it turns out at that
width, and draws into the box the layout gave it. None owns a timer, so anything that moves is
advanced by whatever is driving the frames.

* `StatusBar` — label and value pairs on one row, separators configurable, cut from the right with
  an ellipsis when the row is too narrow
* `ProgressBar` — a fraction from zero to one drawn as a filled run and an empty one, with an
  optional percentage label and an optional `TermBuf::Blend` so a gradient can colour the fill;
  in indeterminate mode a block slides across at a phase the caller advances
* `SingleValue` — one number made prominent, with a caption under it, coloured by where it falls
  against a list of thresholds or by a block
* `FormattedNumber` — a number with grouping separators, fixed decimals, an optional sign and an
  optional unit
* `BytesDisplay` — a byte count in IEC or SI units to a given precision, stepping up a unit rather
  than rounding to a whole base
* `Rating` — a value out of a maximum drawn in stars, read-only by default, editable with the
  arrow keys, `Home`, `End`, the digit keys and a click

```crystal
bar = TermBuf::Widgets::ProgressBar.new 0.4
bar.label = TermBuf::Widgets::ProgressBar::Placement::Centre

stars = TermBuf::Widgets::Rating.new 3.5
stars.editable = true
```

### Data

Widgets that put a source of rows on the screen without building a widget per row. Each asks its
source only for the rows that are showing, the way `VirtualList` does, so what it costs is the size
of the window rather than the size of the data.

* `Table` — rows in columns over a `Rows` source, with a header that stays put while the rows
  scroll. A column carries a header, a `Layout::Sizing`, an alignment, a block that answers what a
  row says in it and an optional block for what to draw that in. Cells are cut with an ellipsis and
  measured under the tree's width policy, so a row with an emoji in it still lines up. Columns
  wider than the table scroll sideways, and it is a `Scrolls` on both axes, so a scrollbar attaches
  to either. Emits `Table::Selected` and `Table::Activated`
* `DataGrid` — a `Table` with a focused column as well as a row, moved with `Left` and `Right`;
  `Enter` opens a `Field` over the cell and a commit emits `DataGrid::Edited`; `#sort_by` orders the
  rows through an index map, leaving the source untouched; the selection covers a row, a cell or any
  number of rows picked with the space bar
* `Tree` — nodes from a `Nodes` source flattened into the rows of a `VirtualList`, which the tree
  holds as its one child. `Right` and `Left` open and close a node, `Enter` uses one, and children
  are asked for once, the first time a node is opened, so a source that loads a level at a time
  loads each level once. The expander glyphs fall back to ASCII on a terminal that would draw the
  triangles two cells wide

```crystal
table = TermBuf::Widgets::Table.new TermBuf::Widgets::Rows.of(people)
table.add_column "name", ->(person : Person) { person.name }
table.add_column "age", ->(person : Person) { person.age.to_s },
  TermBuf::Widgets::Layout::Sizing.fixed(3)

tree = TermBuf::Widgets::Tree.new TermBuf::Widgets::Nodes.from(roots,
  children: ->(path : Path) { entries_of path },
  label: ->(path : Path) { path.basename })
```

## Development

```bash
shards install
crystal spec -v --error-trace
crystal tool format
ameba
```

Specs run with `Layout::Tree.verify_invalidation` on, which lays a clean tree out again and raises
when a rectangle moved without anything having said so. Anything the layout reads goes through
`Widget.layout_property` for that reason.

## License

MIT. See [LICENSE](LICENSE).
