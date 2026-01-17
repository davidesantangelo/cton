# frozen_string_literal: true

RSpec.describe Cton::Binary do
  it "round-trips binary payloads" do
    data = { "user" => { "id" => 1, "name" => "Ada" }, "tags" => %w[a b] }
    binary = Cton.dump_binary(data)

    expect(Cton.load_binary(binary)).to eq(data)
  end

  it "supports uncompressed payloads" do
    data = { "value" => 42 }
    binary = Cton.dump_binary(data, compress: false)

    expect(Cton.load_binary(binary)).to eq(data)
  end
end
