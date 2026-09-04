# The display group: widgets that show a number or a state and take no input,
# with the one exception of a `TermBuf::Widgets::Rating` told it is editable.
#
# * `TermBuf::Widgets::StatusBar` — label and value pairs on one row.
# * `TermBuf::Widgets::ProgressBar` — a fraction, or a sliding block when there
#   is no fraction to give.
# * `TermBuf::Widgets::SingleValue` — one number made prominent, coloured by
#   where it falls against a set of thresholds.
# * `TermBuf::Widgets::FormattedNumber` — a number with grouping separators,
#   fixed decimals, a sign and a unit.
# * `TermBuf::Widgets::BytesDisplay` — a byte count in IEC or SI units.
# * `TermBuf::Widgets::Rating` — a value out of a maximum, drawn in stars.
#
# Every one of them is a leaf: it says how wide it wants to be, how tall it
# turns out at that width, and draws into the box the layout gave it. None
# owns a timer, so anything that moves — a progress bar's indeterminate
# phase — is advanced by whatever is driving the frames.

require "./display/status_bar"
require "./display/progress_bar"
