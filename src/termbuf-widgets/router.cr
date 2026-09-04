require "./focus"
require "./keymap/matcher"
require "./message"
require "./widget"

module TermBuf::Widgets
  # What a key binding does when it fires.
  alias Action = Proc(Context, Nil)

  # A keymap of those, which is what a widget and a focus scope each carry.
  alias Bindings = Keymap(Action)

  # An event aimed at a place on the screen rather than at whatever has the
  # keyboard.
  #
  # `TermBuf` has no mouse event yet. Any event that includes this is routed by
  # position: the router asks `Layout::Tree#hit` what is under the point and
  # starts the chain there. When a mouse event does land, it includes this and
  # nothing here changes.
  module Positioned
    # Column the event happened at, in buffer coordinates.
    abstract def x : Int32

    # Row it happened at.
    abstract def y : Int32
  end

  # What a handler is told about the event it is answering, and how it says it
  # answered.
  #
  # A widget that reacts to an event without calling `#consume` lets it carry
  # on to its parent, which is what a panel highlighting itself on a key it
  # does not otherwise care about wants.
  class Context
    # The router doing the dispatch, and the way to the focus stack and the
    # tree.
    getter router : Router

    # What is being answered.
    getter event : Event

    # The widget the chain started at, which is not the widget being asked.
    getter target : Widget?

    # The widget being asked, which walks up the chain as the dispatch does.
    property widget : Widget?

    # Whether anything has claimed the event.
    getter? consumed : Bool = false

    def initialize(@router : Router, @event : Event, @target : Widget? = nil)
    end

    # Claims the event, which stops the walk.
    def consume : Nil
      @consumed = true
    end

    # Where the keyboard is.
    def focus : Focus::Stack
      @router.focus
    end

    # The tree being dispatched into.
    def tree : Layout::Tree
      @router.tree
    end
  end

  # Where an event goes, and who gets a say in it.
  #
  # A key goes to whatever has the keyboard, a positioned event to whatever is
  # under the point, and a message to whatever contains the widget that sent
  # it. From there the event walks up through the parents until something
  # claims it or it reaches the top scope's root, which is where a modal stops
  # it.
  #
  # Bindings come first, all of them at once. The chain's keymaps go to one
  # `Keymap::Matcher`, innermost first, because a multi-key binding is only a
  # sequence if the same matcher sees every key of it: feeding one keymap per
  # hop would throw away the prefix between hops. Whatever the matcher does not
  # claim is offered to each widget's `Widget#handle` in turn.
  class Router
    include Mailbox

    # The tree being dispatched into.
    getter tree : Layout::Tree

    # Where the keyboard is.
    getter focus : Focus::Stack

    # The state between the keys of a multi-key binding. One per router, reset
    # whenever the keyboard moves: half a sequence typed at one widget means
    # nothing at the next.
    getter matcher = Keymap::Matcher.new

    # Messages emitted since the last drain, in the order they were sent.
    getter pending = [] of Post

    @last_focus : Widget? = nil

    def initialize(@tree : Layout::Tree, @focus : Focus::Stack)
      @tree.root.mailbox = self
    end

    # Sends *event* into the tree, answering whether anything claimed it.
    #
    # *from* is the widget a message came from; the chain starts at its parent,
    # so a widget never answers its own message.
    def dispatch(event : Event, from : Widget? = nil) : Bool
      chain = chain_from start_of(event, from)
      context = Context.new self, event, chain.first?

      return true if fired? event, chain, context

      chain.each do |widget|
        context.widget = widget
        widget.handle event, context
        break if context.consumed?
      end

      context.consumed?
    end

    # Every binding the current chain would answer, innermost first, each with
    # the widget it came from. `nil` for one that came from the focus scope
    # rather than from a widget. What a help overlay lists.
    def active_bindings(from : Widget? = nil) : Array({Keymap::Binding(Action), Widget?})
      found = [] of {Keymap::Binding(Action), Widget?}

      chain_from(from || @focus.current).each do |widget|
        keymap = widget.keymap
        next unless keymap

        keymap.bindings.each { |binding| found << {binding, widget.as(Widget?)} }
      end

      if scoped = @focus.top.keymap
        scoped.bindings.each { |binding| found << {binding, nil.as(Widget?)} }
      end

      found
    end

    # Takes a message from *source*. See `Widget#emit`.
    def post(message : Message, source : Widget) : Nil
      @pending << Post.new(message, source)
    end

    # Delivers everything emitted since the last drain, answering how many that
    # was.
    #
    # One pass: a message emitted by a handler running here waits for the next
    # drain, so a pair of widgets answering each other cannot spin a frame.
    def drain : Int32
      return 0 if @pending.empty?

      posts = @pending.dup
      @pending.clear
      posts.each { |post| dispatch post.message, post.source }

      posts.size
    end

    # The widgets that get a say, *node* first, up to and including the top
    # scope's root.
    private def chain_from(node : Widget?) : Array(Widget)
      chain = [] of Widget
      barrier = @focus.top.root

      while node
        chain << node
        break if node.same? barrier

        node = node.parent
      end

      chain
    end

    # Where the chain starts.
    private def start_of(event : Event, from : Widget?) : Widget?
      return from.try(&.parent) if event.is_a? Message
      return @tree.hit event.x, event.y if event.is_a? Positioned

      @focus.current
    end

    # Whether a binding claimed the key. Also true while the matcher is holding
    # the first keys of a sequence, since those belong to the binding rather
    # than to whatever the widget does with ordinary input.
    private def fired?(event : Event, chain : Array(Widget), context : Context) : Bool
      return false unless event.is_a? Events::Key

      reset_on_focus_change
      result = @matcher.feed event.key, maps_for(chain)
      return true if result.pending?

      binding = result.binding
      return false unless binding

      context.consume
      binding.action.call context
      true
    end

    # The keymaps in scope, innermost first, the focus scope's last.
    private def maps_for(chain : Array(Widget)) : Array(Bindings)
      maps = [] of Bindings
      chain.each { |widget| widget.keymap.try { |keymap| maps << keymap } }
      @focus.top.keymap.try { |keymap| maps << keymap }
      maps
    end

    # Half a sequence typed at one widget means nothing at the next.
    private def reset_on_focus_change : Nil
      held = @focus.current
      return if held.same? @last_focus

      @matcher.reset
      @last_focus = held
    end
  end
end
