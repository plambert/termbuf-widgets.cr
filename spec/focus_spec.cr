require "./spec_helper"

Spectator.describe TermBuf::Widgets::Focus::Stack do
  alias Box = Fixtures::Box
  alias Focus = TermBuf::Widgets::Focus

  # A box that focus can land on.
  def target(width : Int32 = 2) : Box
    made = Box.sized width, 1
    made.focusable = true
    made
  end

  describe "the ring" do
    it "visits the focusable widgets parents first, in declaration order" do
      root = Box.new
      first = target
      middle = Box.new
      inner = target
      middle.add inner
      last = target
      root.add first, middle, last

      expect(Focus::Scope.new(root).ring).to eq [first, inner, last]
    end

    it "leaves out anything that cannot take focus" do
      root = Box.new
      plain = Box.sized 2, 1
      wanted = target
      root.add plain, wanted

      expect(Focus::Scope.new(root).ring).to eq [wanted]
    end

    it "leaves out a hidden widget and everything under it" do
      root = Box.new
      shown = target
      buried = Box.new
      buried.hidden = true
      buried.add target
      root.add shown, buried

      expect(Focus::Scope.new(root).ring).to eq [shown]
    end

    it "includes the root itself when the root can take focus" do
      root = target
      inner = target
      root.add inner

      expect(Focus::Scope.new(root).ring).to eq [root, inner]
    end

    it "reaches into a float" do
      root = Box.new
      flowing = target
      floating = target
      floating.floating = TermBuf::Widgets::Layout::Floating.new
      root.add flowing, floating

      expect(Focus::Scope.new(root).ring).to eq [flowing, floating]
    end
  end

  describe "moving the keyboard" do
    def three : {Focus::Stack, Box, Box, Box}
      root = Box.new
      first = target
      second = target
      third = target
      root.add first, second, third

      {Focus::Stack.new(root), first, second, third}
    end

    it "starts on the first focusable widget" do
      stack, first, _, _ = three
      expect(stack.current).to be first
    end

    it "moves on and wraps at the end" do
      stack, first, second, third = three

      expect(stack.next).to be second
      expect(stack.next).to be third
      expect(stack.next).to be first
    end

    it "moves back and wraps at the start" do
      stack, first, _, third = three

      expect(stack.current).to be first
      expect(stack.previous).to be third
    end

    it "answers nothing when nothing can take focus" do
      stack = Focus::Stack.new Box.new

      expect(stack.current).to be_nil
      expect(stack.next).to be_nil
    end
  end

  describe "#focus" do
    it "puts the keyboard where it is asked" do
      stack, _, second, _ = begin
        root = Box.new
        first = target
        second = target
        third = target
        root.add first, second, third
        {Focus::Stack.new(root), first, second, third}
      end

      expect(stack.focus(second)).to be_true
      expect(stack.current).to be second
    end

    it "refuses a widget that cannot take focus" do
      root = Box.new
      plain = Box.sized 2, 1
      root.add target, plain
      stack = Focus::Stack.new root

      expect(stack.focus(plain)).to be_false
    end

    it "refuses a widget outside the top scope" do
      root = Box.new
      outside = target
      dialog = Box.new
      inside = target
      dialog.add inside
      root.add outside, dialog

      stack = Focus::Stack.new root
      stack.push dialog

      expect(stack.focus(outside)).to be_false
      expect(stack.focus(inside)).to be_true
    end

    it "finds a widget added since the last rebuild" do
      root = Box.new
      root.add target
      stack = Focus::Stack.new root

      late = target
      root.add late

      expect(stack.focus(late)).to be_true
    end
  end

  describe "scopes" do
    def layered : {Focus::Stack, Box, Box, Box, Box}
      root = Box.new
      first = target
      second = target
      dialog = Box.new
      inner = target
      dialog.add inner
      root.add first, second, dialog

      {Focus::Stack.new(root), first, second, dialog, inner}
    end

    it "moves only inside the top scope" do
      stack, _, _, dialog, inner = layered
      stack.push dialog

      expect(stack.current).to be inner
      expect(stack.next).to be inner
    end

    it "gives the keyboard back where it was when the scope is popped" do
      stack, _, second, dialog, _ = layered
      stack.focus second
      stack.push dialog
      stack.pop

      expect(stack.current).to be second
    end

    it "never pops the application's own scope" do
      stack, _, _, _, _ = layered

      expect(stack.pop).to be_nil
      expect(stack.scopes.size).to eq 1
    end
  end

  describe "#rebuild" do
    it "keeps the keyboard on the widget that has it" do
      root = Box.new
      first = target
      second = target
      root.add first, second
      stack = Focus::Stack.new root
      stack.focus second

      root.add target
      stack.rebuild

      expect(stack.current).to be second
    end

    it "moves the keyboard when the widget holding it goes away" do
      root = Box.new
      first = target
      second = target
      root.add first, second
      stack = Focus::Stack.new root
      stack.focus second

      root.remove second
      stack.rebuild

      expect(stack.current).to be first
    end

    it "answers nothing when the last focusable widget goes away" do
      root = Box.new
      only = target
      root.add only
      stack = Focus::Stack.new root

      root.remove only
      stack.rebuild

      expect(stack.current).to be_nil
    end
  end
end
