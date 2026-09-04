require "termbuf"

# Widgets for `TermBuf`, and the layout engine that places them.
#
# A widget is both the thing that draws and the element the layout engine
# sizes: there is no separate declaration tree to keep in step with the
# objects. Build a tree of widgets, hand its root to a `Layout::Tree`, and ask
# for a layout; every widget comes back with a `Rect` in buffer coordinates
# that it can draw into.
module TermBuf::Widgets
  {% begin %}
  {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}
end

require "./termbuf-widgets/layout/errors"
require "./termbuf-widgets/layout/padding"
require "./termbuf-widgets/layout/sizing"
require "./termbuf-widgets/layout/floating"
require "./termbuf-widgets/layout/text_measure"
require "./termbuf-widgets/message"
require "./termbuf-widgets/widgets/border"
require "./termbuf-widgets/widget"
require "./termbuf-widgets/layout/tree"
require "./termbuf-widgets/layout/engine"
require "./termbuf-widgets/editing/completion"
require "./termbuf-widgets/editing/history"
require "./termbuf-widgets/editing/line_buffer"
require "./termbuf-widgets/editing/editor"
require "./termbuf-widgets/widgets/label"
require "./termbuf-widgets/widgets/field"
require "./termbuf-widgets/widgets/paste_notice"
require "./termbuf-widgets/keymap/keymap"
require "./termbuf-widgets/keymap/matcher"
require "./termbuf-widgets/focus"
require "./termbuf-widgets/router"
require "./termbuf-widgets/renderer"
require "./termbuf-widgets/app"
