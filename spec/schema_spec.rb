# frozen_string_literal: true

RSpec.describe Cton::Schema do
  let(:schema) do
    Cton.schema do
      object do
        key "user" do
          object do
            key "id", integer
            key "name", string
            optional "role", enum("admin", "viewer")
          end
        end
        key "tags", array(of: string)
        optional "meta" do
          object(allow_extra: true) do
            key "created_at", string
          end
        end
      end
    end
  end

  it "validates a matching payload" do
    data = {
      "user" => { "id" => 1, "name" => "Ada", "role" => "admin" },
      "tags" => %w[core fast],
      "meta" => { "created_at" => "2025-01-01", "extra" => "ok" }
    }

    result = Cton.validate_schema(data, schema)
    expect(result.valid?).to be true
  end

  it "captures missing keys and type issues" do
    data = {
      "user" => { "id" => "nope", "name" => "Ada", "role" => "invalid" },
      "tags" => ["core", 12]
    }

    result = Cton.validate_schema(data, schema)

    expect(result.valid?).to be false
    messages = result.errors.map(&:message).join(" ")
    expect(messages).to include("Unexpected type")
    expect(messages).to include("Unexpected value")
  end

  it "tracks unexpected keys" do
    data = {
      "user" => { "id" => 1, "name" => "Ada", "extra" => "no" },
      "tags" => ["core"]
    }

    result = Cton.validate_schema(data, schema)
    expect(result.valid?).to be false
    expect(result.errors.map(&:message)).to include("Unexpected key")
  end
end
