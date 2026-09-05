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
# * `TermBuf::Widgets::Spinner` — a frame of an animation that says something
#   is still going on.
# * `TermBuf::Widgets::Clock` — the time of day, kept up to date.
# * `TermBuf::Widgets::RelativeTime` — how long ago something was, in words.
# * `TermBuf::Widgets::DateDisplay` — a date, written and left alone.
# * `TermBuf::Widgets::Icon` — one glyph, with a plainer spelling for the
#   terminals that would draw it ragged.
# * `TermBuf::Widgets::Picture` — a picture over the cells it is given, with
#   words for the terminals that draw no pictures.
#
# Most of them are leaves: each says how wide it wants to be, how tall it turns
# out at that width, and draws into the box the layout gave it. None owns a
# clock, so anything that moves on its own — a spinner's frame — is turned by a
# timer the application lends it through `TermBuf::Widgets::Ticking`, and
# anything that moves without one — a progress bar's indeterminate phase — is
# advanced by whatever is driving the frames.

require "./display/attached"
require "./display/readout"
require "./display/spinner"
require "./display/clock"
require "./display/relative_time"
require "./display/date_display"
require "./display/picture"
require "./display/icon"
require "./display/status_bar"
require "./display/progress_bar"
require "./display/single_value"
require "./display/formatted_number"
require "./display/bytes_display"
require "./display/rating"
