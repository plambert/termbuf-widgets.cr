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

### Input

The widgets a form is made of live under `src/termbuf-widgets/widgets/input/`. Each of them says
what happened to it with a `Message` and knows nothing about what that means; the widget that
contains it answers the message in `Widget#handle`.

```crystal
require "termbuf-widgets"

include TermBuf::Widgets

form = Panel.new direction: :column, gap: 1
name = ValidatedField.new prompt: Field::Prompt.new("name: ")
name.validators << Validators.required

form.add name,
  MaskedField.new(prompt: Field::Prompt.new("word: ")),
  CheckboxGroup.new(%w[email sms post], max: 2),
  ButtonGroup.new(%w[Save Cancel])
```

#### What there is

* **`Button`** — a label that says `Button::Pressed` when `Enter`, `Space` or a click reaches it.
  A disabled button is out of the tab order and answers nothing, but is still drawn: a control
  that vanishes when it cannot be used tells the user less than one that is visibly unavailable.
* **`ButtonGroup`** — a row or a column of buttons that the arrows along it move between. An
  exclusive group is a radio set and says `ButtonGroup::Changed` when the choice moves.
* **`Checkbox`** — a box that is ticked or not, toggled by `Space` or a click, saying
  `Checkbox::Changed`. The marks are measured before they are used and an ASCII pair is taken
  wherever the pretty one does not come out at a cell each.
* **`CheckboxGroup`** — a column of boxes answering one question, with `min` and `max` bounds on
  how many may be ticked. A toggle that would break a bound is put back and the group says
  `CheckboxGroup::Refused` instead of `Changed`.
* **`TextArea`** — somewhere to type more than one line. `Enter` breaks the line, up and down move
  by drawn row keeping the column they set out from, and `#accept_keys` hands the text over.
* **`Field`** — one line to type on, with history, completion and a prompt.
* **`ValidatedField`** — a field holding its line to a list of rules, drawing the first refusal
  under the line and saying `ValidatedField::Invalid` in place of `Field::Accepted`.
* **`MaskedField`** — a validated field drawing a mark for every character, with `#value` for the
  text as typed and `#reveal?` for showing it.
* **`Validators`** — `required`, `length`, `matches`, `numeric`, `one_of`, and `all` to compose
  them. A rule is a `Proc(String, String?)`, so an application's own rules are written where they
  belong rather than as subclasses.

#### Handing the text over

`Enter` cannot hand a `TextArea` over, because it is what puts the line break in. `Ctrl+Enter` is
what everyone reaches for, and only a terminal speaking the kitty keyboard protocol can report it:
`Enter` is the byte `0x0D` and control does not change it, so anywhere else `Ctrl+Enter` arrives as
a plain `Enter`. `TextArea.default_accept_keys` is therefore both `Ctrl+Enter` and `Alt+Enter`, and
`#accept_keys` takes whatever an application would rather use.

### Overlays

The widgets drawn over the screen rather than beside it live under
`src/termbuf-widgets/widgets/overlay/`. Each of them is a float that is put up with `#open` and
taken down with `#close`, and each takes the same three things with it: itself, a `Catcher` one z
below that answers every point the overlay did not so a click cannot reach what is behind it, and
an optional `Backdrop` one below that which dims what is there.

```crystal
dialog = TermBuf::Widgets::Dialog.new "Unsaved changes",
  body: TermBuf::Widgets::Label.new("Save before leaving?"),
  actions: %w[Save Discard Cancel]
dialog.open app
```

A modal overlay pushes a focus scope with itself as the root, so tab moves inside it and a key
nothing in it claims stops there rather than reaching the window behind. Closing pops the scope and
gives the keyboard back to whatever had it. The overlay stays in the tree, hidden, so opening it
again costs nothing and the message it emits on the way down still has a parent to reach.

* **`Dialog`** — a centred box with a title, a body and a `ButtonGroup` of actions. Modal with a
  backdrop by default. `Escape` closes it with nothing chosen and `Enter` presses the default
  action; either way it says `Dialog::Closed` carrying the index of the action or `nil`.
  `Dialog.confirm` and `Dialog.alert` are the two everyone writes anyway.
* **`Popover`** — a box hanging off another widget by a pair of `Layout::AttachPoint`s, which flips
  to the other side of its target rather than going off the screen. Not modal: the rest of the
  screen keeps the keyboard. A click anywhere else takes it down instead of pressing what it landed
  on.
* **`DropdownMenu`** — a popover holding a `VirtualList` of items, each with an optional key hint,
  an enabled flag and a submenu marker. Up and down move past anything disabled, `Enter` and a
  click choose, and it says `DropdownMenu::Selected`. There is no menu bar: a row of buttons each
  opening one of these is what a menu bar is.
* **`Drawer`** — a panel against one edge of the screen, as long as that edge and `#size` cells
  deep. Nothing animates; a program wanting it to slide moves `#size` a cell at a time between
  frames. Says `Drawer::Closed`.
* **`Toasts`** — a stack of short messages in a corner. The newest is always nearest the corner, so
  a bottom stack grows upward and a top one downward; past `#max_visible` the oldest is pushed off.
  A click takes one down, and so does its time running out.
* **`HelpOverlay`** — a dialog listing `Router#active_bindings` for the chain the keyboard is in,
  grouped by the widget each binding came from and scrolling when there are more than fit.
  `HelpOverlay.install app` binds it to `F1` and `?` by merging them into `App#keymap`, which
  leaves whatever was bound there.

#### Timers

Nothing in the widget layer opens a device, and a clock is a device. An application that wants a
toast to time out hands `App` the terminal's:

```crystal
app.after = ->(span : Time::Span) { terminal.after span }
app.cancel = ->(nonce : UInt64) { terminal.cancel nonce }
```

`App#after(span) { ... }` then arms one and runs the block when the `TermBuf::Events::Timer`
arrives; `App#cancel(nonce)` withdraws it. Without those two procs nothing is armed and a toast
stays up until it is clicked.

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
