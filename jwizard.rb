require "securerandom"
require "jwt"
require "clipboard"

class JWizard
  PROMPTS = {
    starting: "Starting with JWT token generation.",
    asking_for_key: "Enter key %d",
    asking_for_value: "Enter %s value",
    asking_for_more_data: "Any additional inputs? (y/n)",
    asking_another: "Generate another token? (y/n)",
    invalid_value: "Invalid %s entered!",
    token_copied: "The JWT has been copied to your clipboard!"
  }.freeze

  VALIDATORS = {
    # lightweight solution (http://emailregex.com)
    "email" => -> (email) { (email =~ /\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i).zero? }
  }.freeze

  TRANSITIONS = {
    asking_for_key: :reading_key,
    asking_for_value: :reading_value,
    asking_for_more_data: :reading_more_data,
    asking_another: :reading_another
  }.freeze

  def initialize(secret: nil, required_payload_fields: [], clipboard: Clipboard)
    @secret = secret || SecureRandom.random_bytes
    @required_payload_fields = required_payload_fields
    @output = nil
    @state = nil
    @key = nil
    @payload = {}
    @clipboard = clipboard
  end

  def run
    loop do
      @state, @output = step
      puts @output if @output
      break if :done == @state
    end
  end

  private

  def step
    case @state
    when nil
      [:asking_for_key, prompt(:starting)]

    when :asking_for_key, :asking_for_value, :asking_for_more_data, :asking_another
      [TRANSITIONS[@state], prompt(@state)]

    when :reading_key
      @key = get_user_input

      :asking_for_value

    when :reading_value
      value = get_user_input

      if valid_value?(@key, value)
        @payload[@key] = value
        @key = nil

        :validating
      else
        [:asking_for_value, prompt(:invalid_value)]
      end

    when :reading_more_data
      process_answer(
        :asking_for_key,
        lambda do
          @clipboard.copy(JWT.encode(@payload, @secret, 'HS256'))

          [:asking_another, prompt(:token_copied)]
        end
      )

    when :reading_another
      process_answer(:starting, :done)

    when :validating
      if valid?
        :asking_for_more_data
      else
        :asking_for_key
      end

    end
  end

  def valid?
    (@required_payload_fields - @payload.keys).empty?
  end

  def valid_value?(key, value)
    if VALIDATORS.key?(key)
      VALIDATORS[key].call(value)
    else
      true
    end
  end

  def prompt(state)
    value = case state
            when :asking_for_key
              @payload.size + 1
            when :asking_for_value, :invalid_value
              @key
            end

    PROMPTS[state] % value
  end

  def get_user_input
    gets.chomp
  end

  def process_answer(y_case, n_case)
    value = get_user_input.downcase

    call_or_return('y' == value[0] ? y_case : n_case)
  end

  def call_or_return(block)
    if block.respond_to?(:call)
      block.call
    else
      block
    end
  end
end

def run!
  JWizard.new(secret: ARGV[0], required_payload_fields: %w[user_id email]).run
end

run! if __FILE__ == $PROGRAM_NAME
