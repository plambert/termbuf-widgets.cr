# Fixtures the input widget specs share.
#
# The name carries the `_spec` suffix because everything under `spec/` that
# does not is a linter warning, and the directories the runner treats as
# support live elsewhere. There are no examples in here.
module Fixtures
  # A panel that writes down every message that reaches it.
  #
  # Messages bubble from the emitter's parent upward, so a log at the root of
  # a tree sees everything anything in it had to say. It claims nothing, which
  # leaves the tree behaving as it would without one.
  class MessageLog < TermBuf::Widgets::Panel
    # Every message that reached this widget, in the order they arrived.
    getter seen = [] of TermBuf::Widgets::Message

    def handle(event : TermBuf::Event, context : TermBuf::Widgets::Context) : Nil
      @seen << event if event.is_a? TermBuf::Widgets::Message
    end

    # The messages of one kind, which is what a spec asking about one widget
    # wants out of a log that hears from several.
    def of(kind : Klass.class) : Array(Klass) forall Klass
      @seen.compact_map &.as?(Klass)
    end

    # Throws away what has been heard so far.
    def forget : Nil
      @seen.clear
    end
  end

  # Pumps *app* until nothing more comes of it.
  #
  # One pump delivers the events waiting and one more delivers the messages
  # they caused, since a message emitted while an event is being answered is
  # held over to the next drain.
  def self.settle(app : TestApp, rounds : Int32 = 4) : Nil
    rounds.times { break if app.pump.zero? }
  end

  # Sends *keys* and lets everything they caused be delivered.
  def self.presses(app : TestApp, keys : String) : Nil
    press app, keys
    settle app
  end

  # Sends a mouse report at (*x*, *y*) and lets it settle.
  def self.mouse(app : TestApp, action : TermBuf::Input::Mouse::Action,
                 x : Int32, y : Int32,
                 button : TermBuf::Input::Mouse::Button = TermBuf::Input::Mouse::Button::Left) : Nil
    app.events.send TermBuf::Events::Mouse.new(button, x, y, TermBuf::Modifiers::None, action)
    settle app
  end

  # A press and a release at the same place, which is a click.
  def self.click(app : TestApp, x : Int32, y : Int32) : Nil
    mouse app, TermBuf::Input::Mouse::Action::Press, x, y
    mouse app, TermBuf::Input::Mouse::Action::Release, x, y
  end
end
