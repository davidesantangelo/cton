# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "cton"
require "json"

schema_path = ENV.fetch("CTON_SCHEMA_PATH", nil)
if schema_path
  require schema_path
  schema = if Object.const_defined?(:CTON_SCHEMA)
             Object.const_get(:CTON_SCHEMA)
           elsif Object.respond_to?(:cton_schema)
             Object.cton_schema
           end
end

input = $stdin.read

if ENV["CTON_TO_BINARY"] == "1"
  data = JSON.parse(input)
  print Cton.dump_binary(data)
  exit 0
end

if ENV["CTON_FROM_BINARY"] == "1"
  data = Cton.load_binary(input)
  print JSON.generate(data)
  exit 0
end

mode = ENV.fetch("CTON_MODE", "to_json")

data = if mode == "to_cton"
         JSON.parse(input)
       else
         Cton.load(input)
       end

if schema
  result = Cton.validate_schema(data, schema)
  unless result.valid?
    warn result
    exit 1
  end
end

output = if mode == "to_cton"
           Cton.dump(data)
         else
           JSON.generate(data)
         end

print output
