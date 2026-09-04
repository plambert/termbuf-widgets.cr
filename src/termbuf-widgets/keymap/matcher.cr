require "./keymap"

module TermBuf::Widgets
  # The state between the keys of a multi-key binding.
  #
  # A router keeps one matcher and feeds it every key press along with the
  # keymaps in scope, innermost first. The matcher is the only thing that
  # knows a prefix has been typed: a keymap answers about a sequence, and it
  # is the matcher that remembers what the sequence is so far.
  #
  # ```
  # matcher = Keymap::Matcher.new
  #
  # matcher.feed prefix, [keymap]             # => pending
  # matcher.feed Key.character('c'), [keymap] # => bound, with the binding
  # ```
  class Keymap::Matcher
    # Which of the three things happened to a key.
    enum State
      # A binding fired.
      Bound

      # The keys so far are a prefix of a binding, so nothing has happened
      # yet and the matcher is holding them.
      Pending

      # No map in scope wanted the keys. The key belongs to whatever the
      # widget does with ordinary input.
      Unbound
    end

    # What feeding a key produced.
    #
    # *binding* and *keymap* are set only for `State::Bound`, and *keymap* is
    # the map the binding came from, which a router needs in order to dispatch
    # against the right widget.
    record Result(U), state : State, binding : Binding(U)? = nil, keymap : Keymap(U)? = nil do
      # Whether a binding fired.
      def bound? : Bool
        @state.bound?
      end

      # Whether the matcher is holding the keys for the next one.
      def pending? : Bool
        @state.pending?
      end

      # Whether the key fell through to the widget.
      def unbound? : Bool
        @state.unbound?
      end
    end

    # The keys typed so far that are a prefix of some binding, in canonical
    # form. Empty except partway through a sequence.
    getter pending = [] of Key

    # Feeds *key* to *maps*, which are in bubbling order: innermost first.
    #
    # Precedence between the maps is deliberate. A map that says `Pending`
    # holds the key however many maps below it said `None`, because the
    # alternative is firing a short binding that makes a longer one in an
    # outer map unreachable. Among maps that would fire, the first one wins,
    # so an inner widget shadows the bindings around it.
    #
    # A prefix followed by a key that nothing wants is dropped rather than
    # replayed: the keys were held on the promise of a binding that did not
    # arrive, and delivering them late to a text widget would insert
    # characters the user typed as a command.
    def feed(key : Key, maps : Array(Keymap(U))) : Result(U) forall U
      sequence = @pending + [Alias.normalise(key)]

      fired : {Keymap(U), Binding(U)}? = nil
      holding = false

      maps.each do |keymap|
        match, binding = keymap.lookup sequence

        case match
        in .pending? then holding = true
        in .bound?   then fired ||= {keymap, binding} if binding
        in .none?    then nil
        end
      end

      if holding
        @pending = sequence
        return Result(U).new State::Pending
      end

      @pending = [] of Key

      if fired
        keymap, binding = fired
        Result(U).new State::Bound, binding, keymap
      else
        Result(U).new State::Unbound
      end
    end

    # Drops any half typed sequence.
    #
    # A router calls this when the thing the keys were going to act on is
    # gone: focus moved, the buffer closed, the mode changed.
    def reset : Nil
      @pending = [] of Key
    end
  end
end
