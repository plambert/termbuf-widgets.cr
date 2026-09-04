module TermBuf::Widgets
  # A table of key sequences and what they mean.
  #
  # A keymap is generic over the action so that the thing a binding names is
  # the application's own data rather than a closure the map has to keep
  # alive: an editor whose actions are an enum can put a keymap in a
  # configuration file, print it, and rebind it, none of which is possible
  # once the action is a proc.
  #
  # Bindings live at the leaves of a trie, so a sequence is either a complete
  # binding or a prefix of longer ones and never both. `^V^A` binds and `^V`
  # then cannot, which is what makes `lookup` able to answer "this is not a
  # binding yet, but keep reading" without guessing at a timeout.
  #
  # ```
  # keymap = Keymap(Symbol).build do |map|
  #   map.bind Key.character('s', Modifiers::Ctrl), "save", :save
  #   map.bind [prefix, Key.character('c')], "close", :close
  # end
  #
  # keymap.lookup [prefix] # => {Keymap::Match::Pending, nil}
  # ```
  class Keymap(T)
    # One binding: the sequence that fires it, what to tell the user it does,
    # and the action itself.
    #
    # The keys are the normalised form, so a binding written as `Ctrl+I` comes
    # back reading `Tab`.
    record Binding(U), keys : Array(Key), description : String, action : U do
      # The sequence as a key binding table would print it: `Ctrl+X Ctrl+S`.
      def to_s(io : IO) : Nil
        @keys.join io, ' '
      end
    end

    # What a sequence turned out to be.
    enum Match
      # Exactly a binding.
      Bound

      # A strict prefix of one or more bindings, so the next key decides.
      Pending

      # Nothing in the map starts with it.
      None
    end

    # A binding that cannot be added because of one already in the map.
    #
    # Sequences collide three ways, and all of them are a mistake in the
    # binding table rather than something to resolve at run time: the same
    # sequence twice, a sequence that is a strict prefix of a bound one, and a
    # sequence that extends a bound one.
    class Conflict < Exception
      # The sequence already in the map.
      getter existing : Array(Key)

      # The sequence that could not be added.
      getter attempted : Array(Key)

      def initialize(@existing : Array(Key), @attempted : Array(Key), message : String)
        super message
      end
    end

    # The keys a terminal cannot tell apart.
    #
    # `Ctrl+I` and `Tab` are both `0x09` on the wire, `Ctrl+M` and `Enter` are
    # both `0x0D`, and `Ctrl+H` is the other byte that means backspace. A
    # binding table that treats them as separate keys has bindings in it that
    # can never fire, so both spellings are folded onto one key on the way in:
    # the named one, which is what `TermBuf`'s decoder emits and what a user
    # reading the table expects to see.
    module Alias
      # The named key each `Ctrl`-modified letter stands for.
      NAMES = {
        'i' => Key::Name::Tab,
        'm' => Key::Name::Enter,
        'h' => Key::Name::Backspace,
      }

      # *key* in its canonical form.
      #
      # `Ctrl` is what the aliasing is about, so it is the modifier that comes
      # off; anything else held down at the same time stays, and a terminal
      # able to report `Alt+Tab` still binds it separately from `Tab`.
      def self.normalise(key : Key) : Key
        return key unless key.ctrl?

        without_ctrl = key.modifiers & ~Modifiers::Ctrl

        if key.character?
          name = NAMES[key.char.downcase]?
          return name ? Key.named(name, without_ctrl) : key
        end

        # `0x08` decodes to `Ctrl+Backspace` and `0x7F` to `Backspace`, and
        # both are the key the user calls backspace.
        return Key.named Key::Name::Backspace, without_ctrl if key.is? Key::Name::Backspace

        key
      end

      # Every key in *keys* in its canonical form.
      def self.normalise(keys : Array(Key)) : Array(Key)
        keys.map { |key| normalise key }
      end

      # One key or a sequence of them, as a sequence in canonical form.
      def self.sequence(keys : Array(Key) | Key) : Array(Key)
        case keys
        in Key        then [normalise(keys)]
        in Array(Key) then normalise(keys)
        end
      end
    end

    # One key of a sequence.
    #
    # A node either holds a binding or has children, never both: `#bind`
    # refuses anything that would make it both, which is what lets `lookup`
    # answer `Pending` for every node that is not a leaf.
    class Node(U)
      # What comes next, by key.
      getter children = {} of Key => Node(U)

      # The binding that ends here, for a leaf.
      property binding : Binding(U)? = nil

      # A binding at or under this node, for naming the other half of a
      # `Conflict`.
      def first_binding : Binding(U)?
        if binding = @binding
          return binding
        end

        @children.each_value do |child|
          if found = child.first_binding
            return found
          end
        end

        nil
      end
    end

    # What `Keymap.build` yields: a keymap that can only be bound to.
    struct Builder(U)
      def initialize(@keymap : Keymap(U))
      end

      # Binds *keys* to *action*. See `Keymap#bind`.
      def bind(keys : Array(Key) | Key, description : String, action : U) : Binding(U)
        @keymap.bind keys, description, action
      end
    end

    # Every binding, in the order it was defined.
    #
    # This is the order a help screen wants: the trie is a lookup structure
    # and has no order worth showing anyone.
    getter bindings = [] of Binding(T)

    private getter root : Node(T) = Node(T).new

    # Builds a keymap from a block of `Builder#bind` calls.
    #
    # ```
    # Keymap(Symbol).build do |map|
    #   map.bind Key.named(Key::Name::Escape), "cancel", :cancel
    # end
    # ```
    def self.build(& : Builder(T) ->) : Keymap(T)
      keymap = new
      yield Builder(T).new keymap
      keymap
    end

    # Binds *keys* to *action*, described to the user as *description*.
    #
    # *keys* is one key or a sequence of them. Raises `Conflict` if the
    # sequence is already bound, is a prefix of a bound sequence, or extends
    # one.
    def bind(keys : Array(Key) | Key, description : String, action : T) : Binding(T)
      sequence = Alias.sequence keys
      raise ArgumentError.new "a binding needs at least one key" if sequence.empty?

      check sequence

      node = root
      sequence.each do |key|
        node = node.children[key] ||= Node(T).new
      end

      binding = Binding(T).new sequence, description, action
      node.binding = binding
      @bindings << binding
      binding
    end

    # Binds a whole `Binding`, keeping its description and action.
    def bind(binding : Binding(T)) : Binding(T)
      bind binding.keys, binding.description, binding.action
    end

    # What *keys* is: a binding, the start of one, or neither.
    #
    # The binding comes back only for `Match::Bound`; `Pending` says to keep
    # the keys and feed the next one, which is what `Matcher` does.
    def lookup(keys : Array(Key)) : {Match, Binding(T)?}
      node = root

      Alias.normalise(keys).each do |key|
        child = node.children[key]?
        return {Match::None, nil} if child.nil?
        node = child
      end

      if binding = node.binding
        {Match::Bound, binding}
      elsif node.children.empty?
        {Match::None, nil}
      else
        {Match::Pending, nil}
      end
    end

    # A new keymap holding both maps' bindings, with *other* winning.
    #
    # An identical sequence in *other* replaces this map's binding where it
    # stands, so a user's overrides do not reshuffle the help screen. A
    # sequence that only overlaps — a prefix of one of this map's bindings, or
    # an extension of one — is still a `Conflict`, because there is no
    # sensible thing to do with a user who bound `^X` over a map that binds
    # `^X^S` except tell them.
    def merge(other : Keymap(T)) : Keymap(T)
      overrides = {} of Array(Key) => Binding(T)
      other.bindings.each { |binding| overrides[binding.keys] = binding }

      merged = Keymap(T).new
      mine = Set(Array(Key)).new

      bindings.each do |binding|
        mine << binding.keys
        merged.bind overrides[binding.keys]? || binding
      end

      other.bindings.each do |binding|
        merged.bind binding unless mine.includes? binding.keys
      end

      merged
    end

    # Raises `Conflict` if *sequence* cannot be added.
    #
    # Separate from the insertion so that a refused binding leaves no half
    # built path behind in the trie.
    private def check(sequence : Array(Key)) : Nil
      node = root

      sequence.each do |key|
        if bound = node.binding
          raise Conflict.new bound.keys, sequence,
            "#{describe sequence} extends the bound #{describe bound.keys}"
        end

        child = node.children[key]?
        return if child.nil?
        node = child
      end

      if bound = node.binding
        raise Conflict.new bound.keys, sequence, "#{describe sequence} is already bound"
      end

      if existing = node.first_binding
        raise Conflict.new existing.keys, sequence,
          "#{describe sequence} is a prefix of the bound #{describe existing.keys}"
      end
    end

    private def describe(sequence : Array(Key)) : String
      sequence.join ' '
    end
  end
end
