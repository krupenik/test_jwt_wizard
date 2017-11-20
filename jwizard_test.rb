require "minitest/autorun"
require_relative "jwizard"

describe JWizard do
  # Public interface for the class is just `new` and `run`, unit testing involves lots of `instance_variable_get|set`

  describe "valid?" do
    it "must be false when some required fields are missing and true when all required fields are present" do
      @subject = JWizard.new(required_payload_fields: %w[f1 f2])

      refute @subject.send(:valid?)

      @subject.instance_variable_set(:@payload, {"f1" => "value"})

      refute @subject.send(:valid?)

      @subject.instance_variable_set(:@payload, {"f1" => "value", "f2" => "value"})

      assert @subject.send(:valid?)
    end
  end

  describe "valid_value?" do
    before do
      @subject = JWizard.new
    end

    it "must return true when validator is void" do
      assert @subject.send(:valid_value?, "key", "value")
    end

    it "must validate simple emails" do
      refute @subject.send(:valid_value?, "email", "value")
      assert @subject.send(:valid_value?, "email", "valid@email.com")
    end
  end

  describe "prompt" do
    before do
      @subject = JWizard.new
    end

    it "must react to the payload size" do
      assert_equal JWizard::PROMPTS[:asking_for_key] % 1, @subject.send(:prompt, :asking_for_key)

      @subject.instance_variable_set(:@payload, {"f1" => "value"})

      assert_equal JWizard::PROMPTS[:asking_for_key] % 2, @subject.send(:prompt, :asking_for_key)
    end

    it "must react to the current key" do
      key = "key"

      @subject.instance_variable_set(:@key, key)

      assert_equal JWizard::PROMPTS[:asking_for_value] % key, @subject.send(:prompt, :asking_for_value)
      assert_equal JWizard::PROMPTS[:invalid_value] % key, @subject.send(:prompt, :invalid_value)
    end
  end

  describe "call_or_return" do
    it "calls whatever is callable and returns everything else" do
      @subject = JWizard.new

      assert_equal :value, @subject.send(:call_or_return, :value)
      assert_equal :value, @subject.send(:call_or_return, -> { :value })
    end
  end

  describe "process_answer" do
    it "picks the first branch when the user answers 'y' and the second one otherwise" do
      @subject = JWizard.new

      def @subject.get_user_input; "yes"; end
      assert_equal :y_value, @subject.send(:process_answer, :y_value, :n_value)

      def @subject.get_user_input; "no"; end
      assert_equal :n_value, @subject.send(:process_answer, :y_value, :n_value)
    end
  end

  describe "run" do
    before do
      @subject = JWizard.new
    end

    it "runs until `step` returns :done" do
      # Infinite loop testing is left as an exercise for the reader
    end

    it "prints whatever `step` returns as output" do
      def @subject.step; [:done, "Hello, world!"]; end

      out, err = capture_io { @subject.run }

      # Will this work on Windows? 🤔
      assert_equal "Hello, world!\n", out
    end
  end

  describe "step" do
    before do
      @subject = JWizard.new
    end

    it "nil -> asking for key" do
      @subject.instance_variable_set(:@state, nil)

      state, output = @subject.send(:step)

      assert_equal :asking_for_key, state
      assert_equal JWizard::PROMPTS[:starting], output
    end

    it "asking for key -> reading key" do
      @subject.instance_variable_set(:@state, :asking_for_key)

      state, output = @subject.send(:step)

      assert_equal :reading_key, state
      assert_equal JWizard::PROMPTS[:asking_for_key] % 1, output
    end

    it "reading key -> asking for value" do
      @subject.instance_variable_set(:@state, :reading_key)
      def @subject.get_user_input; "key"; end

      state, _ = @subject.send(:step)

      assert_equal :asking_for_value, state
    end

    it "asking for value -> reading value" do
      key = "key"
      @subject.instance_variable_set(:@key, key)
      @subject.instance_variable_set(:@state, :asking_for_value)

      state, output = @subject.send(:step)

      assert_equal :reading_value, state
      assert_equal JWizard::PROMPTS[:asking_for_value] % key, output
    end

    # Based on the predefined "email" validator (also test its existence)
    it "reading value -> asking for value (invalid input)" do
      key = "email"
      @subject.instance_variable_set(:@key, key)
      @subject.instance_variable_set(:@state, :reading_value)
      def @subject.get_user_input; "value"; end

      state, output = @subject.send(:step)

      assert_equal :asking_for_value, state
      assert_equal JWizard::PROMPTS[:invalid_value] % key, output
    end

    it "reading value -> validating" do
      key = "key"
      @subject.instance_variable_set(:@key, key)
      @subject.instance_variable_set(:@state, :reading_value)
      def @subject.get_user_input; "value"; end

      state, _ = @subject.send(:step)

      assert_equal :validating, state
      assert_equal({"key" => "value"}, @subject.instance_variable_get(:@payload))
    end

    it "validating -> asking for key (required fields missing)" do
      @subject = JWizard.new(required_payload_fields: %w(f1 f2))
      @subject.instance_variable_set(:@state, :validating)

      state, _ = @subject.send(:step)

      assert_equal :asking_for_key, state
    end

    it "validating -> asking for more data (required fields present)" do
      @subject = JWizard.new(required_payload_fields: %w(f1 f2))
      @subject.instance_variable_set(:@payload, {"f1" => "v1", "f2" => "v2"})
      @subject.instance_variable_set(:@state, :validating)

      state, _ = @subject.send(:step)

      assert_equal :asking_for_more_data, state
    end

    it "asking for more data -> reading more data" do
      @subject.instance_variable_set(:@state, :asking_for_more_data)

      state, output = @subject.send(:step)

      assert_equal :reading_more_data, state
      assert_equal JWizard::PROMPTS[:asking_for_more_data], output
    end

    it "reading more data -> asking for key (y)" do
      @subject.instance_variable_set(:@state, :reading_more_data)
      def @subject.get_user_input; "yes"; end

      state, _ = @subject.send(:step)

      assert_equal :asking_for_key, state
    end

    it "reading more data -> asking to generate another (n)" do
      clipboard = Minitest::Mock.new
      clipboard.expect(:copy, nil, [String])
      @subject.instance_variable_set(:@state, :reading_more_data)
      @subject.instance_variable_set(:@clipboard, clipboard)
      def @subject.get_user_input; "no"; end

      state, output = @subject.send(:step)

      assert_equal :asking_another, state
      assert_equal JWizard::PROMPTS[:token_copied], output
      clipboard.verify
    end

    it "asking to generate another -> reading another" do
      @subject.instance_variable_set(:@state, :asking_another)
      def @subject.get_user_input; "yes"; end

      state, output = @subject.send(:step)

      assert_equal :reading_another, state
      assert_equal JWizard::PROMPTS[:asking_another], output
    end

    it "reading another -> starting (y)" do
      @subject.instance_variable_set(:@state, :reading_another)
      def @subject.get_user_input; "yes"; end

      state, _ = @subject.send(:step)

      assert_equal :starting, state
    end

    it "reading another -> done (n)" do
      @subject.instance_variable_set(:@state, :reading_another)
      def @subject.get_user_input; "no"; end

      state, _ = @subject.send(:step)

      assert_equal :done, state
    end
  end
end
