require "spectator"
require "../src/termbuf-widgets"
require "./support/box"

alias Layout = TermBuf::Widgets::Layout
alias Sizing = TermBuf::Widgets::Layout::Sizing
alias Rect = TermBuf::Rect
alias Keymap = TermBuf::Widgets::Keymap
alias Key = TermBuf::Key
alias Modifiers = TermBuf::Modifiers

# `Ctrl` plus a letter, the way a terminal reports it.
def ctrl(char : Char) : Key
  Key.character char, Modifiers::Ctrl
end

# A named key with nothing held down.
def named(name : Key::Name) : Key
  Key.named name
end

# Runs *block* and returns the `Keymap::Conflict` it raises.
def conflict(& : ->) : Keymap::Conflict
  yield
  raise "expected a Keymap::Conflict, but nothing was raised"
rescue error : Keymap::Conflict
  error
end
