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
