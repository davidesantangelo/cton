#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require "json"
require_relative "../lib/cton"

ITERATIONS = Integer(ENV.fetch("ITERATIONS", 1_000))
STREAM_SIZE = Integer(ENV.fetch("STREAM_SIZE", 200))

sample_payload = {
  "context" => {
    "task" => "Our favorite hikes together",
    "location" => "Boulder",
    "season" => "spring_2025"
  },
  "friends" => %w[ana luis sam],
  "hikes" => Array.new(STREAM_SIZE) do |idx|
    {
      "id" => idx + 1,
      "name" => "Trail ##{idx + 1}",
      "distanceKm" => (6.0 + ((idx % 5) * 0.5)),
      "elevationGain" => 250 + ((idx % 3) * 50),
      "companion" => %w[ana luis sam][idx % 3],
      "wasSunny" => idx.even?
    }
  end
}

warm_cton = Cton.dump(sample_payload)
warm_json = JSON.generate(sample_payload)

puts "\nEncoding benchmarks (iterations=#{ITERATIONS}, stream_size=#{STREAM_SIZE})"
Benchmark.bm(25) do |bm|
  bm.report("cton dump fast") do
    ITERATIONS.times { Cton.dump(sample_payload) }
  end

  bm.report("cton dump precise") do
    ITERATIONS.times { Cton.dump(sample_payload, decimal_mode: :precise) }
  end

  bm.report("json generate") do
    ITERATIONS.times { JSON.generate(sample_payload) }
  end
end

puts "\nDecoding benchmarks"
Benchmark.bm(25) do |bm|
  bm.report("cton load") do
    ITERATIONS.times { Cton.load(warm_cton) }
  end

  bm.report("json parse") do
    ITERATIONS.times { JSON.parse(warm_json) }
  end
end

puts "\nStreaming decode stress (#{STREAM_SIZE * 2} documents, separator=\"\")"
inline_blob = warm_cton.delete("\n") * 2
Benchmark.bm(25) do |bm|
  bm.report("cton inline load") do
    ITERATIONS.times { Cton.load(inline_blob) }
  end
end
