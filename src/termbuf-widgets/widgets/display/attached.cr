require "../../app"

module TermBuf::Widgets
  # The application a widget was handed, for the two things a widget cannot
  # reach on its own: a clock and the clipboard.
  #
  # Neither belongs to the widget layer. `App#after` and `App#copy` are procs
  # an application wires to its terminal, and a widget that wants one is given
  # the application rather than the device:
  #
  #     spinner.attach app
  #
  # A widget nobody attached still lays out and still draws. It simply never
  # ticks and copies nothing, which is what a widget on an application with no
  # clock and no clipboard does anyway.
  module Attached
    # The application, or `nil` for a widget nobody wired one into.
    getter app : App? = nil

    # Hands *app* over.
    def attach(app : App) : Nil
      @app = app
    end

    # Takes it back, leaving the widget with nothing to ask.
    def detach : Nil
      @app = nil
    end
  end

  # A repeating timer, armed through `App#after` and armed again after every
  # tick.
  #
  # `App#after` is one shot: the registration is dropped as the timer fires, so
  # a widget that wants a repeat arms the next one from inside the last. That
  # is the whole of this, and it is why `#interval` is asked again every time
  # rather than read once — a `RelativeTime` that refreshes every second while
  # it is new and every hour once it is a day old answers a longer span as it
  # ages, with nothing else to change.
  #
  # An application with no clock arms nothing and `#running?` stays false, so a
  # widget costs nothing where there is no way to tick it.
  module Ticking
    include Attached

    # The timer waiting, or `nil` when none is.
    getter nonce : UInt64? = nil

    # How long until the next tick.
    abstract def interval : Time::Span

    # What happens when the timer goes off, before the next one is armed.
    abstract def tick : Nil

    # Whether a timer is waiting.
    def running? : Bool
      !@nonce.nil?
    end

    # Starts ticking on *app*, withdrawing whatever was already waiting.
    def start(app : App) : Nil
      stop
      attach app
      arm
    end

    # Stops, withdrawing whatever was waiting.
    def stop : Nil
      waiting = @nonce
      return unless waiting

      @nonce = nil
      @app.try &.cancel(waiting)
    end

    private def arm : Nil
      running = @app
      return unless running

      @nonce = running.after(interval) do
        @nonce = nil
        tick
        arm
        nil
      end
    end
  end

  # Putting text on the system clipboard, through whatever the application
  # wired `App#copy` to.
  #
  # The terminal is the only thing in the picture with a connection to the
  # window system, and the widget layer does not own the terminal, so a widget
  # that copies is handed the application and asks it. An application with
  # nothing wired in takes nothing, and `#copiable?` says so before anything is
  # tried — which is what lets a control draw itself unavailable rather than
  # look as though it worked.
  module Copyable
    include Attached

    # Whether there is anywhere for a copy to go.
    def copiable? : Bool
      !(@app.try &.copy).nil?
    end

    # Copies *text*, answering whether anything took it.
    def copy(text : String) : Bool
      sink = @app.try &.copy
      return false unless sink

      sink.call text
      true
    end
  end
end
