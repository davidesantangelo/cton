# frozen_string_literal: true

require "open3"
require "json"

RSpec.describe "cton CLI" do
  let(:bin_path) { File.expand_path("../../bin/cton", __dir__) }
  let(:schema_path) { File.expand_path("../schema_helper.rb", __dir__) }
  let(:base_env) do
    {
      "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__),
      "RUBYLIB" => File.expand_path("../../lib", __dir__)
    }
  end
  let(:cton_runner) { File.expand_path("support/cton_runner.rb", __dir__) }

  xit "validates against schema from file" do
    input = "user(id=1)"

    stdout, stderr, status = Open3.capture3(
      base_env.merge("CTON_SCHEMA_PATH" => schema_path, "CTON_MODE" => "to_json"),
      "ruby", cton_runner, stdin_data: input
    )

    expect(stderr).to be_empty
    expect(status.success?).to be true
    expect(stdout.strip).to eq('{"user":{"id":1}}')
  end

  xit "converts JSON to binary and back" do
    input = "{\"a\":1}"
    stdout, stderr, status = Open3.capture3(
      base_env.merge("CTON_TO_BINARY" => "1"),
      "ruby", cton_runner, stdin_data: input
    )

    expect(stderr).to be_empty
    expect(status.success?).to be true

    decoded, err2, status2 = Open3.capture3(
      base_env.merge("CTON_FROM_BINARY" => "1"),
      "ruby", cton_runner, stdin_data: stdout
    )

    expect(err2).to be_empty
    expect(status2.success?).to be true
    expect(JSON.parse(decoded)).to eq({ "a" => 1 })
  end
end
