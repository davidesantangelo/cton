# frozen_string_literal: true

require "stringio"

RSpec.describe "CTON streaming" do
  it "streams newline-delimited documents" do
    io = StringIO.new("a=1\nuser(name=Ana)\n")
    values = Cton.load_stream(io).to_a

    expect(values).to eq([
                           { "a" => 1 },
                           { "user" => { "name" => "Ana" } }
                         ])
  end

  it "writes multiple documents to IO" do
    io = StringIO.new
    Cton.dump_stream([{ "a" => 1 }, { "b" => 2 }], io)
    expect(io.string).to eq("a=1\nb=2")
  end

  it "writes using StreamWriter" do
    io = StringIO.new
    writer = Cton::StreamWriter.new(io)
    writer.write({ "a" => 1 })
    writer.write({ "b" => 2 })

    expect(io.string).to eq("a=1\nb=2")
  end

  it "streams with a custom separator" do
    io = StringIO.new("a=1|b=2|")
    values = Cton.load_stream(io, separator: "|").to_a
    expect(values).to eq([{ "a" => 1 }, { "b" => 2 }])
  end
end
