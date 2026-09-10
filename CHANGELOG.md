# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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

- `Layout::Sizing.percent` is a share of what is left rather than of the whole content box: the
  parent's box, less the gaps between its children, less every sibling already settled at a size,
  meaning the `Fixed` ones and the `Fit` ones. `Grow` siblings still take what the percents leave.
  A row of two fifty percent panes with a one-cell rule between them now fills its box exactly,
  where before the pair claimed the rule's cell as well and the row overflowed by one. `Table`
  resolves its own percent columns the same way, so the sizing means one thing everywhere.
- `Split` no longer asks that the rule's cell be left out of its panes' percentages.

### Added

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
- `examples/widgets.cr` has a sixth page, chosen with `6`: a spinner, a clock, a relative time, a
  date, icons, a picture, a link that shows its address when the keyboard reaches it, and a button
  that copies it.

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
- `examples/widgets.cr` has a fourth page, chosen with `4`: a dialog, a menu, a drawer and a stack
  of toasts, each on a button.
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
- `examples/widgets.cr` has three pages now, chosen with `1`, `2` and `3`: the panes it always had,
  a table of a hundred thousand rows, and a tree that makes each level up when it is asked for.
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
- `examples/widgets.cr` has a fourth page, chosen with `4`: the navigation widgets on one screen.
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
