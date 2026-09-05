require "../../router"

# A mouse event carries a column and a row, so it is aimed at a place on the
# screen rather than at whatever has the keyboard.
#
# The event itself is `termbuf-input`'s and stays there. This says only that it
# is one of the things `TermBuf::Widgets::Router` routes by hit test, which is
# what an editable `TermBuf::Widgets::Rating` needs to be told which star was
# clicked. Reopening the record here rather than asking the input shard to know
# what a layout is keeps the dependency pointing one way.
#
# Including a module a second time is a no-op in Crystal, so this costs nothing
# if the same line lands somewhere more central: delete this file then, and
# nothing about `Rating` changes.
struct TermBuf::Input::Events::Mouse
  include TermBuf::Widgets::Positioned
end
