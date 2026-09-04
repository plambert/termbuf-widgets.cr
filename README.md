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
