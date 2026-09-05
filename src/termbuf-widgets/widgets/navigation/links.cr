module TermBuf::Widgets
  # Interning a hyperlink from inside `Widget#draw`.
  #
  # A `TermBuf::Style` carries a link as a four byte id rather than a string,
  # and the table those ids are handed out by belongs to the buffer being drawn
  # into. A widget is given a `TermBuf::View`, which is a window onto some
  # other surface and possibly onto a window onto another one, so the table is
  # found by walking out through the views to whatever is underneath.
  #
  #     id = Linking.link_id view, "https://example.com"
  #     view.write 0, 0, "example", Style::DEFAULT.linked(id)
  #
  # A surface with no table — a batch being collected, say — answers zero,
  # which is the id meaning no link, so the text is drawn either way. So does a
  # terminal that cannot draw hyperlinks: the id is handed out, and the encoder
  # emits nothing for it without `TermBuf::Capability::Osc8Links`.
  module Linking
    extend self

    # The id *uri* is interned under on the surface behind *view*, or zero when
    # there is nothing behind it that interns links.
    #
    # *id* is OSC 8's own grouping parameter: two runs of cells sharing one are
    # one link as far as the terminal is concerned, which is what makes a link
    # split across two rows highlight as a whole.
    def link_id(view : View, uri : String, id : String? = nil) : LinkId
      return 0_u32 if uri.empty?

      case surface = beneath(view)
      when BufferSurface then surface.buffer.link uri, id
      when Terminal      then surface.link uri, id
      else                    0_u32
      end
    end

    # The surface *view* eventually draws on, however many views deep it is.
    private def beneath(view : View) : Drawing
      surface : Drawing = view
      while surface.is_a? View
        surface = surface.target
      end

      surface
    end
  end
end
