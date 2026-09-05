require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Validators do
  alias Validators = TermBuf::Widgets::Validators

  describe ".required" do
    sample [{"", "required"}, {"   ", "required"}, {"\t", "required"},
            {"a", nil}, {" a ", nil}] do |row|
      it "answers #{row[1].inspect} for #{row[0].inspect}" do
        expect(Validators.required.call(row[0])).to eq row[1]
      end
    end

    it "says what it was told to say" do
      expect(Validators.required("a name").call("")).to eq "a name"
    end
  end

  describe ".length" do
    sample [{"", nil}, {"ab", "between 3 and 5 characters"}, {"abc", nil},
            {"abcde", nil}, {"abcdef", "between 3 and 5 characters"}] do |row|
      it "answers #{row[1].inspect} for #{row[0].inspect}" do
        expect(Validators.length(min: 3, max: 5).call(row[0])).to eq row[1]
      end
    end

    it "counts a ceiling on its own" do
      check = Validators.length max: 2

      expect(check.call("ab")).to be_nil
      expect(check.call("abc")).to eq "at most 2 characters"
    end

    it "lets empty text past, so that a rule about form is not a rule about presence" do
      expect(Validators.length(min: 3).call("")).to be_nil
    end
  end

  describe ".matches" do
    sample [{"", nil}, {"abc", nil}, {"ab1", "not in the right form"}] do |row|
      it "answers #{row[1].inspect} for #{row[0].inspect}" do
        expect(Validators.matches(/\A[a-z]+\z/).call(row[0])).to eq row[1]
      end
    end
  end

  describe ".numeric" do
    sample [{"", nil}, {"12", nil}, {"-12", nil}, {"+1.5", nil},
            {"1.", "a number"}, {"twelve", "a number"}, {"12a", "a number"}] do |row|
      it "answers #{row[1].inspect} for #{row[0].inspect}" do
        expect(Validators.numeric.call(row[0])).to eq row[1]
      end
    end
  end

  describe ".one_of" do
    sample [{"", nil}, {"yes", nil}, {"no", nil},
            {"maybe", "one of yes, no"}, {"Yes", "one of yes, no"}] do |row|
      it "answers #{row[1].inspect} for #{row[0].inspect}" do
        expect(Validators.one_of(%w[yes no]).call(row[0])).to eq row[1]
      end
    end
  end

  describe ".all" do
    it "answers the first rule that refused" do
      check = Validators.all Validators.required, Validators.numeric

      expect(check.call("")).to eq "required"
      expect(check.call("abc")).to eq "a number"
      expect(check.call("12")).to be_nil
    end

    it "takes them as a list as well" do
      check = Validators.all [Validators.required, Validators.length(min: 2)]

      expect(check.call("a")).to eq "at least 2 characters"
    end
  end
end
