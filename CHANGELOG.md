# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `VERSION` is read on Windows too. The compiler runs a macro's command there with no shell, so the
  single quotes around the shard's directory reached `shards` as part of the path, and every build
  that required this shard stopped there. Windows gets the directory in double quotes, which its
  command line honours; elsewhere nothing changes.

## [0.9.0] - 2026-10-04

### Added

- `Sizing#with_min_percent` and `Sizing#with_max_percent`, a floor and a ceiling that are a
  percentage of a `Sizing::Basis`. `Parent`, the default, is the parent's whole content box, which
  differs from `Sizing.percent`'s share of what the settled siblings left. `Component` is the
  nearest component root's content box, or the screen when there is none. `Screen` is the whole
  area the tree is laid out into. Each bound keeps its own basis. They bound every mode on either
  axis, and intersect with `min` and `max`, the floor winning when the two cross. A fixed size is
  capped like any other, so `Sizing.fixed(30).with_max_percent(25)` is thirty cells or a quarter
  of the parent, whichever is smaller.
- `Parent` and `Component` bounds apply only once the parent hands out its box. A `Fit` widget
  capped by one of them reports its full content while its parent is measured. A parent that is
  also `Fit` is sized from that uncapped content and comes out too wide. `Screen` bounds, and
  `Component` bounds with no component root, apply from the start and do not have this limit.
- `Sizing#min_percent`, `#max_percent`, `#min_basis`, `#max_basis`, `#percent_bounds?` and
  `#bounds`, which answers the floor and the ceiling in cells for given bases. `#to_s` shows the
  percentages.
- `Widget#component_root?`, false by default. It makes a widget the basis for `Component` bounds on
  the widgets under it, and affects nothing else.
- `VirtualList#on_measure`, which answers the text a row shows. With it set, the list is as wide as
  its widest row. The width is measured once and kept until `#rows=`, `#on_measure=`,
  `#measure_limit=` or `#remeasure` is called, or the number of rows changes.
- `VirtualList#measure_limit`, the number of rows measured from the first, a thousand unless set.
- `VirtualList#remeasure`, for rows changed in place without their number changing.

### Changed

- `Sizing.percent` across its parent's stacking axis is now held under its `max`. It ignored it
  before.
- `VirtualList#rows=` is now a method of its own. With `#on_measure` set it lays the tree out
  again.

## [0.8.0] - 2026-10-02

### Added

- `Scrolls::Margin`, which says how many rows to keep between the selection and the edge of the
  window: `Margin.none`, `Margin.rows(count)` and `Margin.share(fraction)`. `#rows_for(room)` gives
  the rows for a window of that height, never more than leaves the selection a row of its own.
- `VirtualList#scroll_margin` and `Table#scroll_margin` (and so `DataGrid`), `Margin.none` unless
  set. `#scroll_to` and `#select` keep the selection that far from either edge, except at the ends
  of the list, where there is nothing further to scroll to. `#scroll_by`, `#scroll_to_row` and the
  wheel are not affected. A `SelectionList` or `Tree` takes it through its `#list`.
- `Scrolls#top_for`, the arithmetic both widgets share.

## [0.7.0] - 2026-09-29

### Fixed

- A widget's picture is no longer drawn out of shape. It went across the whole box whatever
  proportions it had, so a cover taller than it is wide came out stretched sideways. `Picture` and
  `Icon` now keep the picture's proportions and centre it in what it does not fill; `Panel`
  stretches, because its picture is a backdrop behind other widgets and one that kept its
  proportions would leave part of the panel bare. All three take `fit:` and all three have a
  `#fit` property, so either behaviour is a word away. The fix itself is in termbuf: see
  `TermBuf::Placement#fit`.

### Added

- `Picture#fit`, `Icon#fit` and `Panel#fit`, and `fit:` on each of their constructors.

### Changed

- Needs termbuf 0.8.

## [0.6.0] - 2026-09-29

### Changed

- Needs termbuf 0.7, and skips termbuf 0.6 entirely: 0.5.0 of this shard was the last to build
  against termbuf 0.5, and nothing here ever asked for 0.6.
- `Widget#place_images(store : ImageStore, frame : Rect)` is now
  `#place_images(frame : ImageStore::Frame, rect : Rect)`. The picture goes through the frame the
  renderer opened rather than straight at the store, which is what makes saying the same thing twice
  free. Every override in the shard changed with it.
- `Renderer.render` no longer empties the image store at the top of every frame, which had each
  widget's picture transmitted again on every repaint — a 400KB cover down an ssh connection per
  keystroke. The whole walk now runs inside one `TermBuf::ImageStore#frame`. A placement an
  application made itself is not that frame's and is left where it is.
- `Picture`, `Panel` and `Icon` hold `TermBuf::Pixels` rather than what used to be called
  `TermBuf::Image`, and own the registry entry those pixels turn into.
  - `Picture#image` and `Icon#image` are now `#pixels`, and `Panel#image` is now `#pixels`.
  - `#image` on all three is the `TermBuf::Image` the pixels were registered as, `nil` until a frame
    has put them up. An application that wants more of the picture than the widget offers reads it
    there.
  - Assigning `#pixels` takes the old picture out of the terminal, so assign when the picture
    changed rather than every frame. Nothing is compared: a widget is told, not asked, and
    comparing a few hundred kilobytes to find out would cost more than it saved.
  - `Picture#image?` is gone. It answered `Bool` for "is there a picture", which beside an `#image`
    answering an `Image?` would be a trap. `#pixels` answers the same question.
  - `Panel.new` takes `pixels:` where it took `image:`, and `Icon.new` likewise.

### Added

- `Pictured`, the module behind the three widgets that carry a picture: it holds the registry entry,
  makes it on the first frame that has a store, and takes it back out of the terminal when the
  pixels change. A widget of one's own that draws a picture includes it and writes one
  `#place_images`.
- `Picture#crop`, `Panel#crop` and `Icon#crop`, which draw a rectangle of the picture rather than
  all of it. Stepping one is how a sheet of sprites becomes an animation. The protocol calls it the
  source rectangle; `crop` is the same thing in a word a reader can guess, and `source` on a widget
  would read as where the picture came from. See `TermBuf::Placement#crop`.

### Fixed

- The suite compiles whatever order `crystal spec` globs its files in. It did not: in some orders
  `DataGrid` failed with `can't infer the type of instance variable '@scroll' of
  TermBuf::Widgets::DataGrid(String)`, and which orders those were came down to the filesystem, so
  the same tree built on tmpfs and not on ext4. 0.5.0 has this too.

  `Scrolls` was included on `Table(T)`, and a call on the `Scrolls`-typed `Scrollbar#target` is
  dispatched over every type that includes the module. Building a `DataGrid(String)` added a member
  and had the compiler type `Table#scroll_y` for it there and then — before `Table(String)`, the
  superclass generic instance that nothing in the shard ever names, existed to copy `@scroll`'s
  declaration from. `DataGrid(T) < Table(T)` is the only generic class here whose superclass is
  another, which is why it was the only one that broke. Annotating `@scroll` does not help: the
  compiler asks for the annotation on `DataGrid(String)`, which is not a thing anyone can write.

  `Viewport` is the fix: a non-generic `Widget` that includes `Scrolls`, holds `#scroll`, `#offset`
  and `#wheel`, and answers `#scroll_x`, `#scroll_y`, `#viewport_size` and `#scroll_by`. `Table(T)`
  and `VirtualList(T)` are both one of these now and neither includes the module itself. A
  non-generic class in the module's place has its instance variables settled once, so no order comes
  into it. Crystal 1.21.1.

## [0.5.0] - 2026-09-11

### Fixed

- `Tab` moves between the panes of the panes page in `examples/widgets.cr`, and the screen says
  which one it landed on. Two things were wrong. `Scrollable` was not focusable, so the page's ring
  held only the `VirtualList` and `Tab` cycled from it to itself; a scroll panel over plain content
  is now focusable, with `Up` and `Down` moving a row, `PageUp` and `PageDown` a window, `Home` and
  `End` the ends and `Left` and `Right` a column on a panel that clips sideways. Only the axes it
  clips are bound, since a binding that matches claims the key. A panel with a focusable widget
  under it stays out of the ring as before and lets that widget take the keyboard. And nothing was
  drawn differently for the change: `VirtualList#on_draw` is now told whether the list has the
  keyboard as well as which row is chosen, and `Panel#focused_border_style` draws a pane's border
  in another style while the keyboard is inside it, so the example marks the chosen row `▸` always
  and reverses it only while the list has the keyboard.
- `Rating` no longer draws a half star as `⯪`. U+2BEA is in few terminal fonts, so a 3.5 out of 5
  came out as three stars, a missing-glyph box and an empty star. Font coverage cannot be probed —
  the width policy measures cells, not whether the font has the character — so the default set,
  `Rating::Glyphs::UNICODE`, spells a half star `★` as well and tells it from a whole one by
  drawing it in `Rating#half_style`: `Rating#filled_style` with a 24 bit foreground halved, or made
  faint where the colour is the terminal's own or a palette entry. `Rating::Glyphs::HALF_STAR` is
  the set that spells the half `⯪`, for an application that knows its font carries it. The ASCII
  set is unchanged.
- An overlay with a backdrop no longer erases the screen behind it. `Overlay::Backdrop` was a
  screen-sized float that filled every cell it covered, and a drawing surface can be written to and
  not read, so the glyphs underneath were replaced by blanks and only a tint of them was left — on
  a black background, nothing at all. There is no backdrop widget any more: the renderer asks each
  root for `Widget#backdrop_wash` and draws every root below a backdrop-bearing overlay through it,
  so the widgets down there draw their own glyphs and the blend only settles the style. An overlay
  above another — a toast over a dialog — is not dimmed by it. `Overlay.dim` halves each channel of
  a 24 bit colour and draws a cell with no colour of its own faint, so the dimming shows on a
  coloured screen and on a black one.

### Changed

- The README opens with a whole program that compiles and then maps the public API: `Widget` and
  its layout properties, the sizing modes, `Layout::Tree` and floats, `Renderer`, `App`, focus,
  routing, messages, `Keymap`, and the widget catalogue a line at a time.
- `VirtualList#on_draw`, `Tree#on_draw` and `SelectionList#on_draw` take one more argument: whether
  the list has the keyboard, after the flag saying whether the row is the chosen one. A block
  written against the old four is a compile error, and takes a fifth parameter to fix. The default
  drawing is unchanged.
- `Widget#focused?` and `Widget#routed_by` moved down from `Interactive` to `Widget`, and
  `Widget#focus_within?` joins them. Knowing where the keyboard is is not something only a control
  needs: a pane wants it in order to draw its border. `Interactive` still carries `#take_focus`,
  `#held?` and `#clicked`, and nothing that included it has to change.
- `Layout::Sizing.percent` is a share of what is left rather than of the whole content box: the
  parent's box, less the gaps between its children, less every sibling already settled at a size,
  meaning the `Fixed` ones and the `Fit` ones. `Grow` siblings still take what the percents leave.
  A row of two fifty percent panes with a one-cell rule between them now fills its box exactly,
  where before the pair claimed the rule's cell as well and the row overflowed by one. `Table`
  resolves its own percent columns the same way, so the sizing means one thing everywhere.
- `Split` no longer asks that the rule's cell be left out of its panes' percentages.

### Added

- `Panel#focused_border_style`, the style a pane's border is drawn in while the keyboard is on it
  or on anything under it, and `Border#with_style`, the copy of a box in another style with its
  title left alone. A lit border is not a geometry change: the layout reads the border the panel
  was given and the renderer reads the one it answers with, and a box is a cell per side either
  way.
- `Scrollable#page`, `#scroll_to_start` and `#scroll_to_end`, which are what its own keys move by,
  and `Scrollable.scrolling`, which builds them for a panel whose clipping has changed since it was
  made.
- Six more display widgets, under `src/termbuf-widgets/widgets/display/`: `Spinner`, `Clock`,
  `RelativeTime`, `DateDisplay`, `Icon`, `Picture`, `Hyperlink` and `CopyButton`. The glyph ones
  measure their preferred spelling under the tree's width policy and take a plainer one where it
  would come out ragged, the way `Rating` already did.
- `Ticking` and `Copyable`, two mixins over `Attached`, which is how a widget reaches the clock and
  the clipboard the widget layer does not own: an application hands the widget the whole `App` with
  `#attach`, and a widget nobody attached simply never ticks and copies nothing. `Ticking` asks
  `#interval` again after every tick, so a `RelativeTime` slows its own refresh down as it ages and
  a `Clock` arms for the next whole second rather than for a flat span.
- `App#copy`, the proc an application wires to `TermBuf::Terminal#clipboard`, beside the `App#after`
  and `App#cancel` it already had. Nothing is written where it is `nil`, and a `CopyButton` draws
  itself unavailable rather than looking as though it worked.
- `Readout`, the base for a widget drawing one line of text it works out for itself, as against a
  `Label` drawing text it was handed.
- `examples/widgets.cr` has six pages, chosen with `1` to `6`: the panes it always had, a table of
  a hundred thousand rows, a tree that makes each level up when it is asked for, the navigation
  widgets, the overlays, and the display widgets that move on their own. Every page says on screen
  what should be there and what each key should do to it.
- The overlay group of widgets, under `src/termbuf-widgets/widgets/overlay/`: `Dialog`, `Popover`,
  `DropdownMenu`, `Drawer`, `Toast` with the `Toasts` that owns them, and `HelpOverlay`. Each is a
  float put up with `#open` and taken down with `#close`; a modal one pushes a focus scope with
  itself as the root, and every one of them carries a zero-sized `Overlay::Catcher` that answers
  the points it did not, so a click cannot reach what is behind it.
- `Overlay#backdrop_wash` and `Widget#backdrop_wash` under it, which is how an overlay dims what is
  behind it: the renderer draws each root through the washes of the roots painted over it.
  `Overlay.dim` is the default one, and `Overlay#backdrop_blend` takes another.
- `Widget#wash`, a `TermBuf::Blend` the renderer hands to the view a widget and everything under it
  draws through, so it settles the ground the renderer fills as well as anything drawn on it.
- `App#after(span, &block)` and `App#cancel(nonce)`, with the `App#after=` and `App#cancel=` procs
  an application wires to `TermBuf::Terminal#after` and `#cancel`. A `TermBuf::Events::Timer` for a
  nonce the application armed runs its block and goes no further; one nobody armed is delivered
  into the tree like any other event. Without the procs nothing is armed.
- `App#keymap=`, which puts a keymap under the application and its base focus scope at once, so
  `app.keymap = app.keymap.merge other` adds a binding without losing the ones that were there.
- The display group of widgets, under `src/termbuf-widgets/widgets/display/`: `StatusBar`,
  `ProgressBar`, `SingleValue`, `FormattedNumber`, `BytesDisplay` and `Rating`. Each is a leaf that
  fits its own content and draws into the box the layout gave it; none owns a timer, so a progress
  bar's indeterminate phase is advanced by the caller.
- `TermBuf::Input::Events::Mouse` includes `TermBuf::Widgets::Positioned`, so the router sends a
  click to whatever is under it. An editable `Rating` answers one.
- The data group of widgets, under `src/termbuf-widgets/widgets/data/`: `Table`, `DataGrid`, `Tree`
  and the `Nodes` source a tree reads. Each asks its source only for the rows that are showing, so
  a table of a hundred thousand rows costs what a table of twenty does. Sorting a grid and
  flattening a tree are the two places that ask for more, and both say so.
- `Button` and `ButtonGroup`. A button says `Button::Pressed` for `Enter`, `Space` and a click that
  goes down and comes up inside it; a group is a row or a column the arrows along it move between,
  and an exclusive one is a radio set saying `ButtonGroup::Changed`.
- `Checkbox` and `CheckboxGroup`. `Space` and a click turn a box over and it says
  `Checkbox::Changed`. A group holds `min` and `max` bounds on how many of its boxes may be ticked,
  puts back a toggle that would break one, and says `CheckboxGroup::Refused` instead of `Changed`.
  The marks are measured under the tree's own width policy, and an ASCII pair is taken wherever the
  pretty one does not come out at a cell each.
- `TextArea`, for typing more than one line. `Enter` breaks the line and up and down move by drawn
  row rather than by line, keeping the column they set out from. It wraps by words, anywhere or not
  at all, grows horizontally, vertically, both or neither, scrolls to keep the cursor in view, and
  says `TextArea::Changed` and `TextArea::Accepted`. What hands the text over is `#accept_keys`,
  which is `Ctrl+Enter` and `Alt+Enter` by default: only a terminal speaking the kitty keyboard
  protocol can tell `Ctrl+Enter` from `Enter`.
- `Validator`, a proc from the text to a message or `nil`, and `Validators` with `required`,
  `length`, `matches`, `numeric`, `one_of` and `all`.
- `ValidatedField`, a `Field` holding its line to a list of rules. A line that passes leaves as
  `Field::Accepted`; one that does not leaves as `ValidatedField::Invalid`, stays in the field so
  that there is something to correct, and has the first refusal drawn under it.
- `MaskedField`, a validated field drawing a mark for every character, with `#value` for the text
  as typed and `#reveal?` for showing it. The mark is measured the way a checkbox's marks are, and
  the scrolling is counted in marks rather than in cells.
- The navigation group of widgets, under `src/termbuf-widgets/widgets/navigation/`:
  `NavigationBar`, `TabbedPanels`, `Breadcrumbs`, `Pagination`, `Disclosure` and
  `DisclosureGroup`.
- `NavigationBar`, a row or column of places to go with a brand at the start and a trailing slot at
  the far end. The arrows move the highlight, `Enter` and a click activate, and it says
  `NavigationBar::Selected` followed by whatever the item itself carries. Too narrow, it gives up
  the trailing slot, then the brand, then the labels for their key hints, then the hints for one
  mark each.
- `TabbedPanels`, a tab strip over a panel showing one child at a time. Hidden tabs are hidden
  widgets, so twenty tabs open cost the layout of one. `Ctrl+PageUp` and `Ctrl+PageDown` move
  between them and take the keyboard into what is now showing; the strip answers the arrows and
  `Enter`, and a closable tab gets a close glyph. Says `TabbedPanels::Changed` and
  `TabbedPanels::Closed`.
- `Breadcrumbs`, the path to here joined by a separator glyph. A crumb with a URI is written as an
  OSC 8 hyperlink as well as being clickable, and crumbs are given up from the left with a leading
  ellipsis, the last one kept whole.
- `Pagination`, previous and next buttons around numbered page buttons with a gap standing in for
  the runs that are not shown. A run of exactly one page is shown rather than hidden behind a gap
  wider than it. `Left`, `Right`, `Home` and `End` move, and it says `Pagination::Changed`.
- `Disclosure` and `DisclosureGroup`. `#expanded` is a layout property, so a closed section costs
  one row whatever is in it; an exclusive group is an accordion. Says `Disclosure::Toggled`.
- `Linking.link_id`, which interns a hyperlink through whatever surface a widget is drawing on by
  walking out through the views to the buffer or terminal underneath.
- `Option(T)`, a label and the value it stands for, which is what the list widgets are over.
- `SelectionList`, a window over options with a mark against the ones chosen. `Space` chooses,
  `Enter` says `SelectionList::Confirmed`, and every change says `SelectionList::Changed`. A
  multiple list is capped by `max_selections` and puts back a choice that would break it, saying
  `SelectionList::Refused` instead. A `filterable` list narrows to what is typed at it through a
  map from the showing rows to the options behind them, so the options are never reordered and a
  choice survives being hidden. The marks are `Checkbox`'s, measured under the tree's own width
  policy.
- `Combobox`, a field with a `SelectionList` floating under it, anchored to the field and flipped
  above it where there is no room below. Typing narrows and opens it, `Up` and `Down` move through
  it without the keyboard leaving the field, `Enter` takes the highlighted option as
  `Combobox::Chosen`, and `Escape` shuts it. `allow_custom` decides whether text that is nobody's
  label is handed over with a `nil` value.
- `KeywordList`, a field with the keywords already typed sitting above it as chips. They wrap, and
  the widget grows downward as they do, because the chips are a widget whose `#height_for_width`
  counts the wrapped rows. `Enter` and `,` add one, completing it to a known slug where the text
  names exactly one; `Backspace` on an empty field selects the last chip and a second one removes
  it; `Left`, `Right`, `Delete` and a click work on that selection.
- `ListSelector`, two selection lists in a `Split` with a column of buttons between them. `Space`,
  `Enter` and a click send a row across, the buttons do it for whatever the keyboard is on or for
  the lot, and `ordering` adds a second column that moves a chosen row up and down. `Tab` moves
  between the parts rather than between every button in them.
- `Form`, labelled fields in a column with a submit and a cancel button. `#submit` asks the rules
  given per field, whatever a `ValidatedField` holds itself to, and the form's own `#rules` about
  every value at once, then says `Form::Submitted` or `Form::Invalid` with the keyboard on the
  first field that was refused. `submit_on_enter` makes `Enter` in a field hand the form over, and
  the accepted line is put back rather than left cleared.
