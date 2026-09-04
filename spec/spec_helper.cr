require "spectator"
require "../src/termbuf-widgets"
require "./support/box"
require "./support/generator"
require "./support/invariants"
require "./support/test_app"
require "./support/harness"

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

# Every spec that lays a tree out is also a check that nothing changed its
# geometry without saying so. See `Layout::Tree.verify_invalidation`.
TermBuf::Widgets::Layout::Tree.verify_invalidation = true
