# The input group: the widgets a form is made of.
#
# * `TermBuf::Widgets::Button` and `TermBuf::Widgets::ButtonGroup` — a label
#   that can be pressed, and a row or column of them the arrows move between.
# * `TermBuf::Widgets::Checkbox` and `TermBuf::Widgets::CheckboxGroup` — a box
#   that is ticked or not, and a set of them answering one question under
#   bounds on how many may be.
# * `TermBuf::Widgets::TextArea` — somewhere to type more than one line.
# * `TermBuf::Widgets::ValidatedField` and `TermBuf::Widgets::MaskedField` —
#   a `TermBuf::Widgets::Field` held to a list of rules, and one drawing a
#   mark per character.
# * `TermBuf::Widgets::Validators` — the rules everyone writes anyway, each a
#   `TermBuf::Widgets::Validator`.
# * `TermBuf::Widgets::Option` — a label and the value it stands for, which is
#   what the three list widgets are over.
# * `TermBuf::Widgets::SelectionList` — a window over options with a mark
#   against the ones chosen.
# * `TermBuf::Widgets::Combobox` — a field with a selection list floating
#   under it, narrowed by what is typed.
# * `TermBuf::Widgets::KeywordList` — a field with the keywords already typed
#   sitting above it as chips.
# * `TermBuf::Widgets::ListSelector` — two lists with a column of buttons
#   between them for sending a row across.
# * `TermBuf::Widgets::Form` — labelled fields in a column, with the rules
#   gathered in one place.
#
# Each of them says what happened to it with a `TermBuf::Widgets::Message` and
# knows nothing about what that means: the widget that contains it answers the
# message in `TermBuf::Widgets::Widget#handle`. A control that cannot be used
# is out of the tab order and answers nothing, but is still drawn, because one
# that vanishes tells the user less than one that is visibly unavailable.

require "./input/interactive"
require "./input/button"
require "./input/button_group"
require "./input/checkbox"
require "./input/checkbox_group"
require "./input/text_area"
require "./input/validators"
require "./input/validated_field"
require "./input/masked_field"
require "./input/selection_list"
require "./input/combobox"
require "./input/keyword_list"
require "./input/list_selector"
require "./input/form"
