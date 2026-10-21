module TermBuf::Widgets
  # How many colors a color widget offers, and how it says which one it holds.
  #
  #     swatch = ColorSwatch.new Color.rgb(0x3080C0), depth: Depth::Indexed256
  #     Depth::Indexed256.describe Color.rgb(0x3080C0) # => "#5f87af 67"
  #
  # `TrueColor` offers every 24 bit color and shows it as it is. `Indexed256`
  # offers the 256 color palette, and shows a color the way a terminal without
  # `TermBuf::Capability::TrueColor` draws it, which is
  # `TermBuf::Color#to_indexed256`. A `ColorSwatch` and a `ColorPicker` each
  # take one, so a setting meant for a 256 color terminal is chosen from the
  # colors that terminal has.
  enum Depth
    # Any 24 bit color.
    TrueColor

    # The 256 color palette.
    Indexed256

    # The color a terminal at this depth draws for *color*.
    #
    # At `TrueColor` that is *color* itself. At `Indexed256` an `Rgb` color
    # becomes the nearest palette index, and an `Indexed` or `Default` one
    # passes through.
    def shown(color : Color) : Color
      true_color? ? color : color.to_indexed256
    end

    # What a color widget writes beside the color.
    #
    # `#rrggbb` for an `Rgb` color at `TrueColor`. A color shown as a palette
    # index gets the index after the hex, `#rrggbb 123`, and the hex is the
    # palette's own value for that index. `Default` is the word "default",
    # since the terminal decides what it looks like.
    def describe(color : Color) : String
      return "default" if color.default?

      drawn = shown color
      hex = Depth.hex drawn
      drawn.indexed? ? "#{hex} #{drawn.index}" : hex
    end

    # Black or white, whichever reads better on *color* as this depth draws
    # it.
    #
    # The choice is by relative luminance, with the sRGB curve undone first.
    # Above 0.179 black has more contrast than white, and below it white has
    # more. At `Indexed256` the two inks are cube indices 16 and 231. A theme
    # is free to remap the sixteen system colors, so system black need not be
    # black.
    def ink(color : Color) : Color
      dark = Depth.luminance(shown(color)) > 0.179
      if true_color?
        dark ? Color.rgb(0, 0, 0) : Color.rgb(255, 255, 255)
      else
        dark ? Color.indexed(16) : Color.indexed(231)
      end
    end

    # `#rrggbb` for *color*'s channels, in lower case.
    def self.hex(color : Color) : String
      red, green, blue = color.channels
      "#%02x%02x%02x" % {red, green, blue}
    end

    # The relative luminance of *color*, from zero for black to one for
    # white, as WCAG defines it.
    def self.luminance(color : Color) : Float64
      red, green, blue = color.channels
      0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    end

    private def self.linear(channel : Int32) : Float64
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
    end
  end
end
