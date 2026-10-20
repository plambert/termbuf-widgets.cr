require "../../../widget"
require "../../label"
require "./rows"

module TermBuf::Widgets
  class Form < Widget
    # The calls that describe rows as data. `Form` and `Section` both take
    # them. Rows given to the form itself go in the unnamed section at the top.
    module Schema
      # Adds *row* where this schema puts its rows, and answers it.
      abstract def add_row(row : Row) : Row

      # A row holding `true` or `false`, drawn as a checkbox.
      def toggle(key : String, label : String, value : Bool = false,
                 help : String? = nil) : ToggleRow
        add_row(ToggleRow.new(key, label, value, help)).as(ToggleRow)
      end

      # A row holding one of *options*, where each option is its own label.
      def choice(key : String, label : String, options : Array(String),
                 value : String? = nil, help : String? = nil) : ChoiceRow
        choice key, label, options.map { |option| {option, option} }, value, help
      end

      # A row holding one of *options*, each a value and the label drawn for
      # it.
      def choice(key : String, label : String, options : Array({String, String}),
                 value : String? = nil, help : String? = nil) : ChoiceRow
        add_row(ChoiceRow.new(key, label, options, value, help)).as(ChoiceRow)
      end

      # A row holding an integer in *range*, stepped by *step*.
      def number(key : String, label : String, value : Int32 = 0,
                 range : Range(Int32, Int32) = 0..100, step : Int32 = 1,
                 bar : Bool = false, help : String? = nil) : NumberRow
        add_row(NumberRow.new(key, label, value, range, step, bar, help)).as(NumberRow)
      end

      # A row holding free text.
      def text(key : String, label : String, value : String = "",
               help : String? = nil, placeholder : String? = nil) : TextRow
        add_row(TextRow.new(key, label, value, help, placeholder)).as(TextRow)
      end

      # A row that is a thing to do. Pressing it emits `Form::Activated`.
      def action(key : String, label : String, hint : String? = nil,
                 help : String? = nil) : ActionRow
        add_row(ActionRow.new(key, label, hint, help)).as(ActionRow)
      end
    end

    # A header and the rows under it.
    #
    #     form.section "Display" do |section|
    #       section.toggle "motion", "Animate the panels", value: true
    #     end
    class Section
      include Schema

      # What the header says, or `nil` for the unnamed section at the top.
      getter name : String?

      # The rows, in the order they were added.
      getter rows = [] of Row

      # The header as drawn, or `nil` for the unnamed section.
      getter header : Label?

      def initialize(@form : Form, @name : String?)
        if name = @name
          label = Label.new name, wrap: Layout::Wrap::None
          label.width = Layout::Sizing.grow
          @header = label
        end
      end

      def add_row(row : Row) : Row
        @form.attach row, self
      end
    end
  end
end
