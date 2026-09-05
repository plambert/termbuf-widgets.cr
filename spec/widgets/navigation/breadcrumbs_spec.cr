require "../../spec_helper"
require "../input/input_harness_spec"

Spectator.describe TermBuf::Widgets::Breadcrumbs do
  alias Breadcrumbs = TermBuf::Widgets::Breadcrumbs
  alias Log = Fixtures::MessageLog

  # Twenty-five cells of trail: four, eight and seven of label with two
  # three-cell joiners between them.
  def trail : Breadcrumbs
    Breadcrumbs.new %w[home projects termbuf]
  end

  def rooted(crumbs : Breadcrumbs) : Log
    root = Log.new
    root.add crumbs
    root
  end

  def app(root : Log, columns : Int32 = 30, rows : Int32 = 2) : Fixtures::TestApp
    made = Fixtures::TestApp.new root, columns, rows
    made.frame
    made
  end

  describe "the trail" do
    it "joins the crumbs with the separator" do
      expect(Fixtures.render(rooted(trail), 30, 1).first).to eq "home › projects › termbuf"
    end

    it "takes the separator it was given" do
      expect(Fixtures.render(rooted(Breadcrumbs.new(%w[a b], separator: "/")), 10, 1).first)
        .to eq "a / b"
    end

    it "is one row tall" do
      made = trail
      Fixtures.render rooted(made), 30, 3

      expect(made.rect.height).to eq 1
    end

    it "draws nothing at all when there are no crumbs" do
      expect(Fixtures.render(rooted(Breadcrumbs.new), 10, 2)).to eq ["", ""]
    end
  end

  describe "running out of room" do
    it "gives up crumbs from the left, saying so with an ellipsis" do
      expect(Fixtures.render(rooted(trail), 22, 1).first).to eq "… › projects › termbuf"
    end

    it "gives up as many as it has to and no more" do
      expect(Fixtures.render(rooted(trail), 20, 1).first).to eq "… › termbuf"
    end

    it "keeps the last crumb whole, giving up the ellipsis for it" do
      expect(Fixtures.render(rooted(trail), 10, 1).first).to eq "termbuf"
    end

    it "cuts the last crumb only when it alone will not fit" do
      expect(Fixtures.render(rooted(trail), 5, 1).first).to eq "term…"
    end

    it "takes the ASCII ellipsis where the pretty one is drawn wide" do
      cjk = TermBuf::Unicode::WidthPolicy::DEFAULT.copy_with ambiguous: 2

      expect(Fixtures.render(rooted(trail), 22, 1, cjk).first).to eq "... › termbuf"
    end

    it "says where it starts" do
      made = trail
      policy = TermBuf::Unicode::WidthPolicy::DEFAULT

      expect(made.start_for(30, policy)).to eq 0
      expect(made.start_for(22, policy)).to eq 1
      expect(made.start_for(20, policy)).to eq 2
    end
  end

  describe "links" do
    it "writes a crumb with a URI as a hyperlink" do
      made = trail
      made.crumbs.first.uri = "file:///home"
      painted = Fixtures.painted rooted(made), 30, 1

      expect(Fixtures.style_at(painted, 0, 0).link).not_to eq 0_u32
      expect(Fixtures.style_at(painted, 7, 0).link).to eq 0_u32
    end

    it "leaves a crumb without one unlinked" do
      painted = Fixtures.painted rooted(trail), 30, 1

      expect(Fixtures.style_at(painted, 0, 0).link).to eq 0_u32
    end
  end

  describe "clicking a crumb" do
    it "says which one it was" do
      made = trail
      root = rooted made
      running = app root

      Fixtures.click running, 1, 0
      said = root.of(Breadcrumbs::Selected)

      expect(said.size).to eq 1
      expect(said.first.index).to eq 0
      expect(said.first.crumb).to be made.crumbs[0]
    end

    it "says nothing for a click on a separator" do
      made = trail
      root = rooted made
      running = app root

      Fixtures.click running, 5, 0

      expect(root.of(Breadcrumbs::Selected)).to be_empty
    end

    it "reads the crumbs off the row as it was last drawn" do
      made = trail
      root = rooted made
      running = Fixtures::TestApp.new root, 20, 2
      running.frame

      # At twenty cells the trail is "… › termbuf", so the only crumb on the
      # row is the last one.
      Fixtures.click running, 5, 0

      expect(root.of(Breadcrumbs::Selected).map &.index).to eq [2]
    end
  end

  describe "changing the trail" do
    it "takes the crumbs after one off" do
      made = trail
      made.truncate 0

      expect(made.crumbs.map &.label).to eq ["home"]
    end

    it "leaves the last crumb alone" do
      made = trail
      made.truncate 2

      expect(made.crumbs.size).to eq 3
    end

    it "takes a whole path at once" do
      made = trail
      made.path = %w[one two]

      expect(Fixtures.render(rooted(made), 20, 1).first).to eq "one › two"
    end
  end
end
