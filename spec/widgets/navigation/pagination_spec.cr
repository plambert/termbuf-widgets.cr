require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::Pagination do
  alias Pagination = TermBuf::Widgets::Pagination
  alias Log = Fixtures::MessageLog

  def rooted(pages : Pagination) : Log
    root = Log.new
    root.add pages
    root
  end

  def app(root : Log, columns : Int32 = 40, rows : Int32 = 2) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  # The row of a pagination as a list of pages, with `nil` where a gap stands
  # in for a run of them.
  def shape_of(pages : Int32, page : Int32, window : Int32 = 1) : Array(Int32?)
    Pagination.new(pages: pages, page: page, window: window).shape
  end

  describe "the window" do
    it "is every page when they all fit inside it" do
      expect(shape_of(5, 3)).to eq [1, 2, 3, 4, 5]
    end

    it "is one page for one page" do
      expect(shape_of(1, 1)).to eq [1]
    end

    it "keeps the first and the last with a gap in between" do
      expect(shape_of(10, 5)).to eq [1, nil, 4, 5, 6, nil, 10]
    end

    it "has no gap on the side the window reaches the end" do
      expect(shape_of(10, 3)).to eq [1, 2, 3, 4, nil, 10]
      expect(shape_of(10, 8)).to eq [1, nil, 7, 8, 9, 10]
    end

    it "has one gap at the first page and one at the last" do
      expect(shape_of(10, 1)).to eq [1, 2, nil, 10]
      expect(shape_of(10, 10)).to eq [1, nil, 9, 10]
    end

    it "shows a single missing page rather than a gap standing for it" do
      expect(shape_of(5, 4, window: 1)).to eq [1, 2, 3, 4, 5]
      expect(shape_of(7, 4, window: 1)).to eq [1, 2, 3, 4, 5, 6, 7]
    end

    it "widens with the window" do
      expect(shape_of(20, 10, window: 0)).to eq [1, nil, 10, nil, 20]
      expect(shape_of(20, 10, window: 3)).to eq [1, nil, 7, 8, 9, 10, 11, 12, 13, nil, 20]
    end
  end

  describe "the row" do
    it "draws the two end buttons around the numbers and the gaps" do
      made = Pagination.new pages: 10, page: 5

      expect(Fixtures.render(rooted(made), 40, 1).first).to eq " <  1  …  4  5  6  …  10  >"
    end

    it "takes the ASCII gap where the pretty one is drawn wide" do
      made = Pagination.new pages: 10, page: 5
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Fixtures.render(rooted(made), 40, 1, cjk).first)
        .to eq " <  1  ...  4  5  6  ...  10  >"
    end

    it "is one row tall" do
      made = Pagination.new pages: 10, page: 5
      Fixtures.render rooted(made), 40, 3

      expect(made.rect.height).to eq 1
    end

    it "marks the button for the page showing" do
      made = Pagination.new pages: 10, page: 5

      expect(made.button_for(5).try &.selected?).to be_true
      expect(made.button_for(4).try &.selected?).to be_false
    end
  end

  describe "the ends" do
    it "disables the button back on the first page" do
      made = Pagination.new pages: 10, page: 1

      expect(made.previous.disabled?).to be_true
      expect(made.following.disabled?).to be_false
    end

    it "disables the button on on the last page" do
      made = Pagination.new pages: 10, page: 10

      expect(made.previous.disabled?).to be_false
      expect(made.following.disabled?).to be_true
    end

    it "disables both when there is only one page" do
      made = Pagination.new pages: 1

      expect(made.previous.disabled?).to be_true
      expect(made.following.disabled?).to be_true
    end
  end

  describe "the keyboard" do
    it "steps a page either way" do
      made = Pagination.new pages: 10, page: 5
      running = app rooted(made)

      Fixtures.presses running, "Right"
      expect(made.page).to eq 6

      Fixtures.presses running, "Left"
      expect(made.page).to eq 5
    end

    it "goes to either end" do
      made = Pagination.new pages: 10, page: 5
      running = app rooted(made)

      Fixtures.presses running, "Home"
      expect(made.page).to eq 1

      Fixtures.presses running, "End"
      expect(made.page).to eq 10
    end

    it "stops at either end rather than wrapping" do
      made = Pagination.new pages: 10, page: 1
      root = rooted made
      running = app root

      Fixtures.presses running, "Left"

      expect(made.page).to eq 1
      expect(root.of(Pagination::Changed)).to be_empty
    end

    it "says which page it went to, once" do
      made = Pagination.new pages: 10, page: 5
      root = rooted made
      running = app root

      Fixtures.presses running, "Right"
      said = root.of(Pagination::Changed)

      expect(said.size).to eq 1
      expect(said.first.page).to eq 6
    end

    it "keeps the keyboard on the page showing" do
      made = Pagination.new pages: 10, page: 5
      running = app rooted(made)

      Fixtures.presses running, "Right"

      expect(running.focused).to be made.button_for(6)
    end
  end

  describe "the pointer" do
    it "goes to the page whose button was clicked" do
      made = Pagination.new pages: 10, page: 5
      root = rooted made
      running = app root

      # " < " then " 1 ", " … ", " 4 ", " 5 ", " 6 " puts page six at 15 to 17.
      Fixtures.click running, 16, 0
      said = root.of(Pagination::Changed)

      expect(made.page).to eq 6
      expect(said.map &.page).to eq [6]
    end

    it "goes back a page on the button that does" do
      made = Pagination.new pages: 10, page: 5
      running = app rooted(made)

      Fixtures.click running, 1, 0

      expect(made.page).to eq 4
    end
  end

  describe "the page set from outside" do
    it "moves the row without saying anything" do
      made = Pagination.new pages: 10, page: 5
      root = rooted made
      running = app root
      made.page = 9
      Fixtures.settle running

      expect(made.shape).to eq [1, nil, 8, 9, 10]
      expect(root.of(Pagination::Changed)).to be_empty
    end

    it "holds the page inside the pages there are" do
      made = Pagination.new pages: 10, page: 5
      made.page = 99

      expect(made.page).to eq 10
    end

    it "brings the page back inside a shorter run of them" do
      made = Pagination.new pages: 10, page: 9
      made.pages = 3

      expect(made.page).to eq 3
      expect(made.shape).to eq [1, 2, 3]
    end

    it "refuses fewer than one page" do
      made = Pagination.new pages: 10, page: 5
      made.pages = 0

      expect(made.pages).to eq 1
      expect(made.page).to eq 1
    end
  end
end
