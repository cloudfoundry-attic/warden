RSpec::Matchers.define :eventually_error_with do |error_type, error_message, timeout=10|
  def supports_block_expectations?
    true
  end

  match do |actual|
    begin
      Timeout::timeout(timeout) do
        begin
          actual.call
          rescue error_type => e
            retry unless e.message =~ error_message
            true
          rescue
            retry
        end
      end
      rescue Timeout::Error
      puts "Timed out waiting on #{error_message}"
    end
  end
end
