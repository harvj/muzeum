require "rails_helper"

RSpec.describe SimpleLogger do
  include SimpleLogger

  describe "#redact" do
    it "redacts the specified key from a query string" do
      query = "method=x&api_key=SECRET123&user=test"

      result = redact(query, :api_key)

      expect(result).to include("api_key=[REDACTED]")
      expect(result).not_to include("SECRET123")
    end

    it "leaves other keys untouched" do
      query = "user=test&limit=200"

      result = redact(query, :api_key)

      expect(result).to eq("user=test&limit=200")
    end

    it "supports multiple sensitive keys" do
      query = "token=ABC&api_key=DEF&user=test"

      result = redact(query, :api_key, :token)

      expect(result).to include("api_key=[REDACTED]")
      expect(result).to include("token=[REDACTED]")
    end
  end
end
