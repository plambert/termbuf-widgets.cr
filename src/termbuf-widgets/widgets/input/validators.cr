module TermBuf::Widgets
  # What a rule about the text in a field comes to: the message to show when
  # the text breaks it, and `nil` when it does not.
  #
  # A validator is a proc rather than a class because a rule is one question
  # asked of one string, and an application's own rules — is this hostname
  # resolvable, is this port free — are written where they belong rather than
  # as subclasses of something in here.
  #
  #     field.validators << Validators.required
  #     field.validators << ->(text : String) { text.starts_with?('/') ? nil : "an absolute path" }
  alias Validator = Proc(String, String?)

  # The rules a form asks often enough that nobody should write them twice.
  #
  # Every one of them answers a `Validator`, so they compose with an
  # application's own and with each other:
  #
  #     Validators.all Validators.required, Validators.length(min: 8)
  #
  # The messages are what a field draws under itself, so they read as the end
  # of a sentence about what was wanted: "at least 8 characters", not "ERROR:
  # length < 8".
  module Validators
    extend self

    # Text with something in it that is not a space.
    def required(message : String = "required") : Validator
      ->(text : String) : String? { text.blank? ? message : nil }
    end

    # Text of at least *min* and at most *max* characters.
    #
    # Empty text passes, so that a field which may be left alone but must be
    # sensible when it is filled in needs one rule rather than two; pair it
    # with `.required` for one that must be filled in.
    def length(min : Int32 = 0, max : Int32? = nil, message : String? = nil) : Validator
      ->(text : String) : String? do
        return if text.empty?
        return if text.size >= min && !(max && text.size > max)

        message || length_message(min, max)
      end
    end

    private def length_message(min : Int32, max : Int32?) : String
      return "between #{min} and #{max} characters" if max && min > 0
      return "at most #{max} characters" if max

      "at least #{min} characters"
    end

    # Text *pattern* matches. Empty text passes; see `.length`.
    def matches(pattern : Regex, message : String = "not in the right form") : Validator
      ->(text : String) : String? do
        return if text.empty? || pattern.matches?(text)

        message
      end
    end

    # A number, with an optional sign and an optional decimal part. Empty text
    # passes; see `.length`.
    def numeric(message : String = "a number") : Validator
      matches NUMBER, message
    end

    # What `.numeric` accepts.
    NUMBER = /\A[+-]?\d+(\.\d+)?\z/

    # One of *allowed*, spelled exactly. Empty text passes; see `.length`.
    def one_of(allowed : Enumerable(String), message : String? = nil) : Validator
      wanted = allowed.to_a

      ->(text : String) : String? do
        return if text.empty? || wanted.includes?(text)

        message || "one of #{wanted.join ", "}"
      end
    end

    # Every one of *validators*, answering the first message any of them has.
    def all(*validators : Validator) : Validator
      all validators.to_a
    end

    # :ditto:
    def all(validators : Enumerable(Validator)) : Validator
      rules = validators.to_a

      ->(text : String) : String? do
        rules.each do |rule|
          message = rule.call text
          return message if message
        end

        nil
      end
    end
  end
end
