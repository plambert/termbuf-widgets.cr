# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
