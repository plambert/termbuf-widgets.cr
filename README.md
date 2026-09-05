# termbuf-widgets

Widgets for [termbuf](https://github.com/plambert/termbuf.cr), and the layout engine that places
them.

A widget is both the thing that draws and the element the layout engine sizes, so there is no
second declaration tree to keep in step with the objects. Build a tree of widgets, hand its root to
a `Layout::Tree`, and every widget comes back carrying a rectangle in buffer coordinates that it
can draw into.

Requires Crystal 1.21 or later.

## Installation

Add the dependency to `shard.yml` and run `shards install`:

```yaml
dependencies:
  termbuf-widgets:
    github: plambert/termbuf-widgets.cr
```

## Input widgets

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

### What there is

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

### Handing the text over

`Enter` cannot hand a `TextArea` over, because it is what puts the line break in. `Ctrl+Enter` is
what everyone reaches for, and only a terminal speaking the kitty keyboard protocol can report it:
`Enter` is the byte `0x0D` and control does not change it, so anywhere else `Ctrl+Enter` arrives as
a plain `Enter`. `TextArea.default_accept_keys` is therefore both `Ctrl+Enter` and `Alt+Enter`, and
`#accept_keys` takes whatever an application would rather use.

## Development

```bash
shards install
crystal spec -v --error-trace
crystal tool format
ameba
```

## License

MIT. See [LICENSE](LICENSE).
