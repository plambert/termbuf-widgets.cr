module TermBuf::Widgets
  # Something a widget has to say to whatever contains it.
  #
  # A widget knows what happened to it and nothing about what that means: a
  # button knows it was pressed, and the dialog around it knows that pressing
  # it means saving the file. A message is how the first tells the second
  # without either holding a reference to the other.
  #
  # ```
  # struct Pressed < TermBuf::Widgets::Message
  # end
  #
  # button.emit Pressed.new
  # ```
  #
  # Messages include `TermBuf::Event`, so a handler answers one the same way it
  # answers a key. They are delivered on the next `App#pump`, from the
  # emitter's parent upward, which is why a widget never sees its own message
  # in the dispatch that emitted it.
  abstract struct Message
    include Event
  end

  # A message waiting to be delivered, and the widget that sent it.
  record Post, message : Message, source : Widget

  # Where `Widget#emit` puts a message.
  #
  # A `Router` is one. A widget finds it the way it finds its tree: by walking
  # to the root, which is the only widget the mailbox is set on.
  module Mailbox
    # Takes a message from *source*, to be delivered on the next pump.
    abstract def post(message : Message, source : Widget) : Nil
  end
end
