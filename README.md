# termbuf-widgets

Widgets and a layout engine for [termbuf](https://github.com/plambert/termbuf.cr).

A widget is both the thing that draws and the element the layout engine sizes, so there is no
separate declaration tree to keep in step with the objects. Build a tree of widgets, hand its root
to a `Layout::Tree`, and every widget comes back carrying a rectangle in buffer coordinates that it
can draw into.

Requires Crystal 1.21 or later.

## Getting started

```yaml
dependencies:
  termbuf-widgets:
    github: plambert/termbuf-widgets.cr
  termbuf:
    github: plambert/termbuf.cr
  termbuf-input:
    github: plambert/termbuf-input.cr
```

This shard pulls the other two in on its own. Name them as well, as above, when your own code
reaches for them directly, which anything that opens a terminal does.

Then `shards install`, and a whole program:

```crystal
require "termbuf-widgets"

alias Widgets = TermBuf::Widgets

TermBuf::Terminal.open do |terminal|
  root = Widgets::Panel.new direction: :column, gap: 1,
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    padding: Widgets::Layout::Padding.all(1)

  field = Widgets::Field.new prompt: Widgets::Field::Prompt.new("name: ")
  root.add Widgets::Label.new("Enter hands the line over. Ctrl+Q leaves."), field

  leaving = false
  quit = Widgets::Bindings.build do |map|
    map.bind TermBuf::Key.parse("Ctrl+Q"), "leave",
      ->(_context : Widgets::Context) { leaving = true; nil }
  end

  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(terminal.size.columns, terminal.size.rows),
    terminal.events, terminal.policy
  app.keymap = app.keymap.merge quit
  app.focus.focus field

  loop do
    app.frame { |spot| terminal.cursor.move_to spot[0], spot[1] if spot }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
```

`App#wait` blocks until the terminal has something to say, delivers it, takes anything else that
came in with it, and answers `false` once the channel has closed. `App#frame` lays out whatever
changed, draws it, and yields where the terminal's cursor belongs. Handlers run only inside a
pump and only set properties, so every hit test in a frame runs against the rectangles that are on
the screen rather than against ones a handler moved halfway through.

`examples/widgets.cr` is the same loop with six pages of widgets on it, and
`crystal run examples/widgets.cr` is the quickest look at the catalogue.

## Layout

### Sizing

Every widget asks to be sized on each axis with a `Layout::Sizing`, held in `Widget#width` and
`Widget#height`:

| Mode | Asks for |
| --- | --- |
| `Sizing.fixed(cells)` | exactly that many cells |
| `Sizing.fit(min, max)` | what the content needs, and no more |
| `Sizing.percent(hundredths)` | that share of what is left of the parent's content box |
| `Sizing.grow(weight, min, max)` | a share, by weight, of whatever is still over |

What a percent is a share *of* is the parent's content box less the gaps between the children and
less every sibling already settled at a size, meaning the fixed ones and the fitting ones. Two
panes at fifty each with a one-cell rule between them fill the box, rather than claiming the rule's
cell twice over and overflowing by one. `Table` resolves its percent columns the same way.

Each of the four is bounded by its own `#min` and `#max`; `#with_min` and `#with_max` answer a copy
with one of them changed.

### Box model

A widget's `#rect` is the whole claim. Inside it, in order, sit the margin, the border, the padding
and the content:

| Reader | Box |
| --- | --- |
| `Widget#rect` | everything the widget asked for |
| `Widget#frame` | the rectangle less the margin: what is filled, and what the border goes around |
| `Widget#content` | what is left after margin, border and padding, and where the children go |
| `Widget#inset` | margin, border and padding together |

A size is the size of the claim, so `Sizing.fixed(10)` with a margin of one is ten cells across
with eight of content. Margins do not collapse.

Children are stacked along `#direction`, `#gap` cells apart, and what is left over is settled by
`#align_x` and `#align_y`.

### Floats

`Widget#floating` lifts a widget out of its parent's flow. It keeps its place in the tree, which is
what makes it a child of the thing it belongs to, but its parent reserves nothing for it: it is
sized and placed against its `Layout::Anchor` after the rest of the tree is settled.

An anchor names a widget to hang off, or the screen, and a pair of `Layout::AttachPoint`s, one on
the float and one on the target, which are laid on top of each other. `Layout::Overflow::Flip`
mirrors the pair when the result would go off the screen, which is how a menu opens upward when
there is no room below; `Clamp` slides it back instead.

### The tree

```crystal
tree = Widgets::Layout::Tree.new root, TermBuf::Rect.full(columns, rows)
tree.layout_if_needed
```

`Layout::Tree` holds the one piece of state the widgets do not: whether the rectangles they carry
are still good. `#roots_in_z_order` is the painting order, the tree's own root first and then every
float by its `Layout::Floating#z`. `#hit` answers what is under a point, trying the roots from the
top down.

Everything the engine reads is reached through `Widget.layout_property`, whose setter marks the
tree dirty. `Layout::Tree.verify_invalidation = true` lays a clean tree out again before every
frame and raises `Layout::MissedInvalidation` when a rectangle moved without anything having said
so. It doubles the cost of a clean frame; specs run with it on.

The engine itself is `Layout::Engine`, a whole-cell reimplementation of the one in
[Clay](https://github.com/nicbarker/clay): six passes over the tree, then a seventh for the floats.

## Widget

`Widget` is what everything on the screen is. These are the layout properties, each of them a
`layout_property` and so each of them safe to assign at any time:

| Property | Says |
| --- | --- |
| `#width`, `#height` | how the widget asks to be sized on each axis |
| `#direction` | which way the children stack |
| `#padding`, `#margin`, `#border`, `#gap` | the box model, and the space between children |
| `#align_x`, `#align_y` | where the children sit in room nobody took |
| `#clip_x?`, `#clip_y?` | whether the edges cut rather than the children compressing |
| `#scroll_x`, `#scroll_y` | how far the content is shifted, read only on a clipped axis |
| `#floating` | placement out of the parent's flow, or `nil` |
| `#hidden?` | skipped entirely: no size, no position, no gap beside it |

`#style` is what the widget draws in, merged onto what it inherited. `#wash` is a `TermBuf::Blend`
every cell it paints settles through. Neither is geometry, so neither invalidates the layout.

A subclass supplies what the engine cannot work out:

| Method | Answers |
| --- | --- |
| `#intrinsic_width(policy)` | a `Layout::Intrinsic`: how narrow the content can go, and what it wants |
| `#height_for_width(width, policy)` | how many rows it turns out to be once the width is settled |
| `#draw(view)` | the drawing, through a view already cut to `#content` |
| `#place_images(store, frame)` | whatever pictures it wants on the screen this frame |
| `#cursor_position` | where the terminal's cursor belongs while it has focus, in its own content box |
| `#focusable?` | whether focus can land here |
| `#handle(event, context)` | what to do with an event no binding claimed |
| `#backdrop_wash` | what everything painted below it is settled through |

`#add`, `#remove` and `#clear` build the tree; `#each_in_tree` walks it; `#at` hit tests one
subtree.

## Focus

`Focus::Stack` is a stack of `Focus::Scope`s, each a subtree, the widgets in it that can take the
keyboard in tab order, and a keymap that layer adds under them. There is always the application's
own; `#push` puts a dialog's on top and `#pop` gives the keyboard back to where it was. `#focus`
refuses a widget outside the top layer, which is what makes a modal overlay modal.

A widget asks where the keyboard is rather than being told:

| Call | True when |
| --- | --- |
| `Widget#focused?` | the keyboard is on this widget |
| `Widget#focus_within?` | it is on this widget or on anything under it |

The pair exists because the control that takes the keyboard and the pane drawn around it are two
widgets. `Panel#focused_border_style` asks `#focus_within?`.

`Scrollable#focusable?` is true only for a panel with nothing focusable under it. A window over
plain content is scrolled by the keyboard and by nothing else, so it takes it; a window over
controls stays out of the tab order and lets them take it, since moving between them scrolls the
window to wherever the next one is.

## Keys

`Keymap(T)` is a table of key sequences and what they mean, generic over the action so that a
binding names the application's own data rather than a closure: an editor whose actions are an enum
can print its keymap, write it to a file and rebind it. `Editor` carries one over
`Editor::Action`.

```crystal
keymap = Widgets::Keymap(Symbol).build do |map|
  map.bind TermBuf::Key.parse("Ctrl+S"), "save", :save
  map.bind TermBuf::Key.parse("Ctrl+X c"), "close", :close
end
```

`TermBuf::Key.parse` answers the whole sequence, so a multi-key binding is one string with spaces
in it.

Bindings live at the leaves of a trie, so a sequence is either a complete binding or a prefix of
longer ones and never both. Binding one that is already bound, that is a prefix of a bound
sequence, or that extends one raises `Keymap::Conflict`. `#lookup` answers `Bound`, `Pending` or
`None`, and `Keymap::Matcher` is what holds the keys of a sequence between presses. `#merge` answers
a keymap holding both, the other map winning where the sequences are identical, which is how a
binding is added without losing what was there.

`Keymap::Alias` folds the spellings a terminal cannot tell apart onto the named key: `Ctrl+I` reads
`Tab`, `Ctrl+M` reads `Enter`, `Ctrl+H` reads `Backspace`.

What a widget and a focus scope each carry is `Bindings`, which is `Keymap(Action)` over
`Action = Proc(Context, Nil)`.

## Routing

`Router` decides where an event goes. A key goes to whatever has the keyboard, an event including
`Positioned` — a mouse event is one — to whatever `Layout::Tree#hit` finds under the point, and a
message to whatever contains the widget that sent it. From there it walks up through the parents
until something claims it or it reaches the top scope's root.

Bindings come first, all of them at once: the chain's keymaps go to one `Keymap::Matcher`,
innermost first, because a multi-key binding is only a sequence if the same matcher sees every key
of it. Whatever the matcher does not claim is offered to each widget's `Widget#handle` in turn.

`Context` is what a handler is told and how it answers:

| Call | Does |
| --- | --- |
| `#consume` | claims the event, which stops the walk |
| `#capture(widget)` | sends every positioned event to that widget until `#release`, which is what a drag needs |
| `#focus`, `#tree`, `#router` | the focus stack, the tree, and the router doing the dispatch |

`Router#active_bindings` lists every binding the current chain would answer, innermost first, each
with the widget it came from. `HelpOverlay` draws it.

## Messages

A widget knows what happened to it and nothing about what that means: a button knows it was
pressed, and the dialog around it knows that pressing it means saving the file.

```crystal
class Save < Widgets::Panel
  def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
    return unless event.is_a? Widgets::Field::Accepted

    save event.text
    context.consume
  end
end
```

`Message` includes `TermBuf::Event`, so a handler answers one the same way it answers a key.
`Widget#emit` walks up to the root's `Mailbox`, which the router sets; delivery is on the next
`App#pump`, starting at the emitter's parent, so a widget never sees its own message in the
dispatch that emitted it. `Router#drain` is one pass, so a pair of widgets answering each other
cannot spin a frame.

## Rendering

`Renderer.render tree, screen, images` is one pre-order walk per root in painting order. Every
widget gets a `TermBuf::View` cut to its own rectangle, addressed from its own top left, nested
inside a second view cut to whatever its nearest clipping ancestor allows. That second view is the
scissor: whatever reaches past the edge of a scroll panel is trimmed on the way through rather than
landing on the panel's neighbours.

Styles layer the same way. A widget's `#style` is merged onto the one it inherited, so a panel that
names a background gives it to everything drawn inside it. Its `#wash` goes to the same view, and
so does the composition of the `#backdrop_wash` of every root painted over it: the widget's own
runs first and the dimming last, so what an overlay dims is the style the widget settled on.

The screen is never cleared, because a clear throws away the scroll hints a widget left behind and
the painter needs those to reach for the terminal's own scrolling region. Each root fills its own
rectangle instead.

## The widgets

### Primitives

| Widget | What it is |
| --- | --- |
| `Panel` | somewhere to put other widgets, with a style, a border and an optional background picture |
| `Label` | a run of text, wrapped and measured under the tree's width policy |
| `Divider` | a rule one cell thick, taking its direction from the parent it was put in |
| `Split` | two panes with a rule between them that can be dragged |
| `Scrollable` | a panel that clips rather than compressing its children, so the edges do the cutting |
| `VirtualList(T)` | a window over a `Rows(T)` source that holds no widget per row |
| `Scrollbar` | where a `Scrolls` has got to, and a handle for moving it |
| `Field` | one line to type on, with history, completion and a prompt |
| `PasteNotice` | a float saying a bracketed paste is arriving, so a long one is not a hung application |
| `Border` | a box around a widget, with an optional title in the top edge |

`Rows(T)` is two questions — how many rows there are, and what row *index* is — so a list of a
hundred thousand costs what a list of twenty does. `Rows.of` wraps an array and `Rows.from` a pair
of blocks. `Scrolls` is what a `Scrollbar` asks of a window: how much there is, how much is
showing, and how far in the window sits. Both `Scrollable` and `VirtualList` are one.

`VirtualList#on_draw` is called with the view, the row's index, the row, whether it is the chosen
one and whether the list has the keyboard. The last two are separate because they are two different
things to draw: a list that has lost focus still knows where its selection is, and a highlight left
lit says the arrows will move it when they will not. `Tree#on_draw` and `SelectionList#on_draw`
take the same five.

```crystal
notes = Widgets::Scrollable.new
lines.each { |line| notes.add Widgets::Label.new(line) }

pane = Widgets::Panel.new border: Widgets::Border.plain(title: " notes ")
pane.focused_border_style = accent
pane.add notes
```

### Display

| Widget | What it is |
| --- | --- |
| `StatusBar` | label and value pairs on one row, cut from the right with an ellipsis |
| `ProgressBar` | a fraction as a filled run and an empty one, or a block sliding when there is no fraction |
| `SingleValue` | one number made prominent, with a caption, coloured against thresholds or by a block |
| `FormattedNumber` | grouping separators, fixed decimals, an optional sign and an optional unit |
| `BytesDisplay` | a byte count in IEC or SI units, stepping up a unit rather than rounding to a whole base |
| `Rating` | a value out of a maximum in stars, read-only by default, editable with the arrows and the digits |
| `Spinner` | a frame of an animation that says work is going on |
| `Clock` | the time of day in a `Time::Format` string, armed for the next whole second |
| `RelativeTime` | "3 minutes ago", refreshing more slowly as the time it describes ages |
| `DateDisplay` | a date in a `Time::Format` string, with no timer, because a date does not change |
| `Icon` | one glyph, with a plainer spelling where the first would not come out at the width reserved |
| `Picture` | a picture over the cells it is given, with alt text for the terminals that draw none |
| `Hyperlink` | text carrying an OSC 8 link, which reveals the address once the keyboard reaches it |
| `CopyButton` | a button that copies what a block answers and flashes a label to say it did |

`Readout` is the base for a widget drawing one line it works out for itself, as against a `Label`
drawing text it was handed.

None of these owns a clock, and none owns the clipboard, because the widget layer opens no device.
A widget that needs one is handed the whole `App` and asks it: `Attached#attach`, with `Ticking`
for a repeating timer through `App#after` and `Copyable` for `App#copy`. A widget nobody attached
lays out and draws as usual; it simply never ticks and copies nothing. `ProgressBar`'s
indeterminate `#phase` has no timer at all and is advanced by whatever is driving the frames.

```crystal
app.after = ->(span : Time::Span) { terminal.after span }
app.cancel = ->(nonce : UInt64) { terminal.cancel nonce }
app.copy = ->(text : String) { terminal.clipboard.copy text }

spinner = Widgets::Spinner.new "working"
spinner.start app

stars = Widgets::Rating.new 3.5
stars.editable = true
```

### Data

| Widget | What it is |
| --- | --- |
| `Table(T)` | rows in columns over a `Rows(T)` source, with a header that stays put while the rows scroll |
| `DataGrid(T)` | a table with a focused column as well as a row, in-place editing, and a sort order beside the source |
| `Tree(T)` | nodes from a `Nodes(T)` source flattened into the rows of a `VirtualList` |
| `Nodes(T)` | where a tree gets what it shows: the roots, a node's children, whether it is a leaf, and its label |

Each of the three widgets asks its source only for the rows that are showing. The two exceptions
say so: sorting a grid asks for every row once, and flattening a tree walks whatever is open. A
table column carries a header, a `Layout::Sizing`, an alignment, a block answering what a row says
in it and an optional block for the style to draw that in. Cells are cut with an ellipsis and
measured under the tree's width policy, so a row with an emoji in it still lines up.

`Nodes#leaf?` is asked separately from `#children` so that the expensive question is asked only for
a node somebody opened. Children are asked for once, the first time a node is expanded.

```crystal
table = Widgets::Table.new Widgets::Rows.of(people)
table.add_column "name", ->(person : Person) { person.name }
table.add_column "age", ->(person : Person) { person.age.to_s },
  Widgets::Layout::Sizing.fixed(3)

tree = Widgets::Tree.new Widgets::Nodes.from(roots,
  children: ->(path : Path) { entries_of path },
  label: ->(path : Path) { path.basename })
```

### Input

| Widget | What it is |
| --- | --- |
| `Button` | a label that says `Button::Pressed` for `Enter`, `Space` and a click |
| `ButtonGroup` | a row or column of buttons the arrows move between; an exclusive one is a radio set |
| `Checkbox` | a box that is ticked or not, toggled by `Space` or a click |
| `CheckboxGroup` | a column of boxes answering one question, with `min` and `max` on how many may be ticked |
| `TextArea` | somewhere to type more than one line, moving by drawn row rather than by line |
| `ValidatedField` | a field holding its line to a list of rules, drawing the first refusal under the line |
| `MaskedField` | a validated field drawing a mark per character, with `#value` for the text as typed |
| `Validator` | `Proc(String, String?)`, with `required`, `length`, `matches`, `numeric`, `one_of` and `all` in `Validators` |
| `Option(T)` | a label and the value it stands for, which is what the list widgets are over |
| `SelectionList(T)` | a window over options with a mark against the ones chosen, single or multiple, filterable |
| `Combobox(T)` | a field with a selection list floating under it, narrowed by what is typed |
| `KeywordList` | a field with the keywords already typed sitting above it as chips, which wrap as they grow |
| `ListSelector(T)` | two lists in a `Split` with a column of buttons between them |
| `Form` | labelled fields in a column, with the rules gathered in one place and a `#submit` that asks them all |

Each of them says what happened to it with a `Message` and knows nothing about what that means. A
disabled control is out of the tab order and answers nothing, but is still drawn: one that vanishes
when it cannot be used tells the user less than one that is visibly unavailable. A group that
refuses a toggle puts it back and says `Refused` rather than `Changed`.

```crystal
form = Widgets::Form.new
form.add "name", Widgets::ValidatedField.new, [Widgets::Validators.required]
form.add "port", Widgets::ValidatedField.new, [Widgets::Validators.numeric]
form.add "colour", Widgets::Combobox.new(Widgets::Option.all(%w[amber azure beige]))
```

`Option` is what a list shows against what the application gets back, which are rarely the same
thing: `Option.all` labels each value by `#to_s`, and `Option.new("ssh", 22)` says both.

`Enter` cannot hand a `TextArea` over, because it is what puts the line break in. Only a terminal
speaking the kitty keyboard protocol can report `Ctrl+Enter`: `Enter` is the byte `0x0D` and
control does not change it. `TextArea.default_accept_keys` is therefore both `Ctrl+Enter` and
`Alt+Enter`, and `#accept_keys` takes whatever an application would rather use.

### Navigation

| Widget | What it is |
| --- | --- |
| `NavigationBar` | a row or column of places to go, giving up the trailing slot, the brand, then the labels as it narrows |
| `TabbedPanels` | a tab strip over a panel showing one child at a time, the others hidden and costing no layout |
| `Breadcrumbs` | the path to here, cut from the left with a leading ellipsis and the last crumb kept whole |
| `Pagination` | previous and next around the page numbers, with a gap standing in for the runs not shown |
| `Disclosure` | a header that opens and closes what is under it |
| `DisclosureGroup` | a set of those, exclusive or not, which is an accordion |

The bar, the crumbs and the tab strip draw their own items rather than holding a widget each:
giving up a label but not the item it belongs to is a decision about the whole row, and the layout
engine apportions space between children without ever asking one to spell itself differently.

`Disclosure#expanded` is a layout property, because a closed section is out of the layout entirely
and costs one row whatever is in it. `TabbedPanels` answers `Ctrl+PageUp` and `Ctrl+PageDown` from
anywhere inside, and moving takes the keyboard into whatever is now showing.

```crystal
panels = Widgets::TabbedPanels.new
panels.add "source", editor
panels.add "output", log, closable: true

sections = Widgets::DisclosureGroup.new exclusive: true
sections.add("advanced").body.add checkbox
```

### Overlays

| Widget | What it is |
| --- | --- |
| `Dialog` | a centred box with a title, a body and a `ButtonGroup` of actions; modal with a backdrop by default |
| `Popover` | a box hanging off another widget, flipping to its other side rather than going off the screen |
| `DropdownMenu` | a popover holding a list of items, each with an optional key hint and an enabled flag |
| `Drawer` | a panel against one edge of the screen, as long as that edge and `#size` cells deep |
| `Toasts` and its `Toast`s | a stack of short messages in a corner, the newest nearest it, the oldest pushed off past `#max_visible` |
| `HelpOverlay` | a dialog listing `Router#active_bindings` for the chain the keyboard is in |

Each is a float put up with `#open` and taken down with `#close`, and each takes an
`Overlay::Catcher` one z below it: a float with no size at all that answers every point the overlay
did not, so a click cannot reach what is behind it. A modal overlay pushes a focus scope with
itself as the root, so tab moves inside it and a key nothing in it claims stops there. Closing pops
the scope. The overlay stays in the tree, hidden, so opening it again costs nothing and a message
it emits on the way down still has a parent to reach.

An overlay asked for a backdrop dims what is behind it without drawing anything there. Before a
frame is painted the renderer asks every root for its `Overlay#backdrop_wash` and draws each root
through the washes of the roots above it, so the widgets down there put their own glyphs on the
screen as they always did and the blend only settles the style each cell comes out with. A toast
opened over a dialog is above it and stays at full colour. `Overlay.dim` does the dimming unless an
overlay names another blend in `#backdrop_blend`: a 24 bit colour has each channel halved, and a
cell with no colour of its own is drawn faint instead, since there is nothing there to halve and an
indexed colour is the terminal's to interpret.

```crystal
dialog = Widgets::Dialog.new "Unsaved changes",
  body: Widgets::Label.new("Save before leaving?"),
  actions: %w[Save Discard Cancel]
dialog.open app

Widgets::HelpOverlay.install app
```

`Dialog.confirm` and `Dialog.alert` are the two everyone writes anyway.
`HelpOverlay.install` binds the overlay to `F1` and `?` by merging them into `App#keymap`, which
leaves whatever was bound there.

## The application

`App` is a widget tree, the surface it is drawn on, and the events it answers. It is given a
`TermBuf::Drawing` and a channel rather than a `TermBuf::Terminal`, so the thing that owns the
device stays outside it: a spec drives one over a `TermBuf::Buffer` with nothing to open or tear
down.

| Property | What an application puts in it |
| --- | --- |
| `#after=`, `#cancel=` | `TermBuf::Terminal#after` and `#cancel`, for anything that ticks |
| `#copy=` | `TermBuf::Terminal#clipboard`, for anything that copies |
| `#images=` | `TermBuf::Terminal#images`, for anything that draws a picture |
| `#keymap=` | the application's own bindings, usually `app.keymap.merge other` |
| `#on_event=` | what to do with an event the tree did not claim |

Left `nil`, each of those means the thing that wanted it does without: nothing is armed, nothing is
copied, no widget is asked for a picture. `App#after(span) { }` arms a one-shot timer and runs the
block when the `TermBuf::Events::Timer` reaches `#pump`; a timer nobody armed is delivered into the
tree like any other event.

`#pump` takes everything waiting without blocking, `#wait` blocks for the first of it, and `#frame`
lays out, draws, and answers the cursor. `#focus`, `#router` and `#tree` are the three pieces
underneath, and `App.default_keymap` is `Tab` and `Shift+Tab`, which every application wants and
none should have to write.

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
