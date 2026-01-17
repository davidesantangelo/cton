# frozen_string_literal: true

require "stringio"

RSpec.describe Cton::Decoder do
  it "provides a scan_stream helper" do
    io = StringIO.new("alpha=1\nbeta=2\n")
    values = described_class.scan_stream(io).to_a

    expect(values).to eq([{ "alpha" => 1 }, { "beta" => 2 }])
  end

  it "supports custom separators" do
    io = StringIO.new("a=1|b=2|")
    values = described_class.scan_stream(io, separator: "|").to_a

    expect(values).to eq([{ "a" => 1 }, { "b" => 2 }])
  end
end
