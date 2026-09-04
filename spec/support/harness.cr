module Fixtures
  # Lays *widget* out on a screen of *columns* by *rows*, draws it through the
  # renderer, and gives back what the screen shows.
  #
  # This is the whole pipeline a widget spec wants: the layout, the clipping
  # and the style merging a real frame does, with the terminal left out.
  def self.render(widget : TermBuf::Widgets::Widget, columns : Int32 = 30, rows : Int32 = 6,
                  policy : TermBuf::Unicode::WidthPolicy = TermBuf::Unicode::WidthPolicy::DEFAULT) : Array(String)
    text_of painted(widget, columns, rows, policy)
  end

  # The same, answering the buffer itself, for a spec asking about styles
  # rather than about characters.
  def self.painted(widget : TermBuf::Widgets::Widget, columns : Int32 = 30, rows : Int32 = 6,
                   policy : TermBuf::Unicode::WidthPolicy = TermBuf::Unicode::WidthPolicy::DEFAULT) : TermBuf::Buffer
    buffer = TermBuf::Buffer.new columns, rows
    buffer.policy = policy
    tree = TermBuf::Widgets::Layout::Tree.new widget, TermBuf::Rect.full(columns, rows), policy
    tree.layout_if_needed
    TermBuf::Widgets::Renderer.render tree, TermBuf::BufferSurface.new(buffer)

    buffer
  end

  # What a buffer shows, one line per row with the trailing blanks cut.
  def self.text_of(buffer : TermBuf::Buffer) : Array(String)
    buffer.to_text.split('\n').map &.rstrip
  end

  # The style one cell of *buffer* carries.
  def self.style_at(buffer : TermBuf::Buffer, x : Int32, y : Int32) : TermBuf::Style
    buffer.styles[buffer.back[x, y].style]
  end

  # Takes a frame and gives back what it drew.
  def self.frame(app : TestApp) : Array(String)
    app.frame
    app.lines
  end

  # Sends *keys*, written the way `TermBuf::Key.parse` reads them, and lets the
  # app answer them.
  def self.press(app : TestApp, keys : String) : Nil
    TermBuf::Key.parse(keys).each { |key| app.events.send TermBuf::Events::Key.new(key, Bytes.empty) }
    app.pump
  end

  # Sends *text* one character at a time, the way somebody typing it would.
  def self.type(app : TestApp, text : String) : Nil
    text.each_char do |char|
      app.events.send TermBuf::Events::Key.new(TermBuf::Key.character(char), Bytes.empty)
    end
    app.pump
  end
end
