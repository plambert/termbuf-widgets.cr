module TermBuf::Widgets
  # What a widget carrying a picture needs: the registry entry for the pixels it
  # holds, made the first frame it sees a store and taken back out of the
  # terminal when the pixels change.
  #
  # A widget holds `TermBuf::Pixels`, which is a value it can be given before
  # there is a terminal in the picture at all. A `TermBuf::Image` is an id a
  # terminal has heard of, so one cannot be made until a frame arrives with a
  # store in it. `#picture_for` is where that happens, and it happens once.
  #
  # The including widget decides what its own properties are called, because a
  # panel's background and an icon's overlay want different names and different
  # depths. What is shared is only the bookkeeping.
  module Pictured
    # The registry entry for this widget's pixels, or `nil` until a frame has put
    # them up.
    #
    # An application that wants to do more with the picture than a widget offers
    # — upload it early, show it somewhere else as well — has it here once a
    # frame has run.
    getter image : TermBuf::Image? = nil

    # The entry to show *pixels* under, registering them if that has not happened
    # yet.
    #
    # Registering again would mint another id and send the picture a second time,
    # so the entry is kept. It is dropped and made again only when the store is
    # not the one it came from, or when something forgot it — a cleared store
    # leaves every entry it handed out dead.
    private def picture_for(frame : TermBuf::ImageStore::Frame,
                            pixels : TermBuf::Pixels) : TermBuf::Image
      held = @image
      return held if held && !held.forgotten? && held.store.same? frame.store

      @image = frame.store.register pixels
    end

    # Takes the picture off the screen and out of the terminal, which is what
    # giving a widget different pixels amounts to.
    private def forget_picture : Nil
      held = @image
      @image = nil
      return if held.nil? || held.forgotten?

      held.forget
    end
  end
end
