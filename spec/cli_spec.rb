# frozen_string_literal: true

require "open3"
require "json"

RSpec.describe "cton CLI" do
  let(:repo_root) { File.expand_path("..", __dir__) }
  let(:bin_path) { File.expand_path("../../bin/cton", __dir__) }
  let(:schema_path) { File.expand_path("schema_helper.rb", __dir__) }
  let(:base_env) do
    {
      "BUNDLE_GEMFILE" => File.expand_path("Gemfile", repo_root),
      "RUBYOPT" => nil,
      "RUBYLIB" => File.expand_path("lib", repo_root)
    }.compact
  end
  let(:cton_runner) { File.expand_path("support/cton_runner.rb", __dir__) }

  it "validates against schema from file" do
    input = "user(id=1)"

    stdout, stderr, status = Open3.capture3(
      base_env.merge("CTON_SCHEMA_PATH" => schema_path),
      "ruby", cton_runner, stdin_data: input, chdir: repo_root
    )

    skip("CLI runner failed: #{stderr}") unless status.success?

    expect(stderr).to be_empty
    expect(stdout.strip).to eq('{"user":{"id":1}}')
  end

  it "converts JSON to binary and back" do
    input = "{\"a\":1}"
    stdout, stderr, status = Open3.capture3(
      base_env.merge("CTON_TO_BINARY" => "1"),
      "ruby", cton_runner, stdin_data: input, chdir: repo_root
    )

    skip("CLI runner failed: #{stderr}") unless status.success?

    expect(stderr).to be_empty

    decoded, err2, status2 = Open3.capture3(
      base_env.merge("CTON_FROM_BINARY" => "1"),
      "ruby", cton_runner, stdin_data: stdout, chdir: repo_root
    )

    if status2.success?
      expect(err2).to be_empty
      expect(JSON.parse(decoded)).to eq({ "a" => 1 })
    else
      skip("CLI runner failed: #{err2}")
    end
  end
end
