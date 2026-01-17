# CTON

[![Gem Version](https://badge.fury.io/rb/cton.svg)](https://badge.fury.io/rb/cton)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidesantangelo/cton/blob/master/LICENSE.txt)

CTON (Compact Token-Oriented Notation) is a token-efficient, JSON-compatible wire format built for LLM prompts. It keeps structure explicit (objects, arrays, table arrays) while removing syntactic noise, so prompts are shorter and outputs are easier to validate. CTON is deterministic and round-trippable, making it safe for LLM workflows.

**CTON is designed to be the reference language for LLM data exchange**: short, deterministic, schema-aware.

---

## Quickstart

```bash
bundle add cton
```

```ruby
require "cton"

payload = {
  "user" => { "id" => 42, "name" => "Ada" },
  "tags" => ["llm", "compact"],
  "events" => [
    { "id" => 1, "action" => "login" },
    { "id" => 2, "action" => "upload" }
  ]
}

cton = Cton.dump(payload)
# => user(id=42,name=Ada)
# => tags[2]=llm,compact
# => events[2]{id,action}=1,login;2,upload

round_trip = Cton.load(cton)
# => same as payload
```

```bash
# CLI usage
cton input.json
cton --to-json data.cton
cton --stats input.json
```

---

## Why CTON for LLMs?

- **Shorter prompts**: CTON removes braces, indentation, and repeated keys.
- **Schema hints built-in**: arrays include length and tables include headers.
- **Deterministic output**: round-trip safe and validates structure.
- **LLM-friendly**: small grammar + clear guardrails for generation.

---

## CTON in 60 seconds

### Objects & Scalars

```text
task=planning,urgent=true,id=123
```

### Nested Objects

```text
user(name=Ada,settings(theme=dark))
```

### Arrays & Tables

```text
tags[3]=ruby,gem,llm
files[2]{name,size}=README.md,1024;lib/cton.rb,2048
```

---

## LLM Prompt Kit (Recommended)

System prompt template:

```markdown
You are an expert in CTON (Compact Token-Oriented Notation). Convert between JSON and CTON following the rules below and preserve the schema exactly.

Rules:
1. Do not wrap the root in `{}`.
2. Objects use `key=value` and nested objects use `key(...)`.
3. Arrays are `key[N]=v1,v2` and table arrays are `key[N]{k1,k2}=v1,v2;v1,v2`.
4. Use unquoted literals for `true`, `false`, and `null`.
5. Quote strings containing reserved characters (`,`, `;`, `=`, `(`, `)`) or whitespace.
6. Always keep array length and table headers accurate.
```

Few-shot example:

```text
JSON: {"team":[{"id":1,"name":"Ada"},{"id":2,"name":"Lin"}]}
CTON: team[2]{id,name}=1,Ada;2,Lin
```

---

## Schema Validation (1.0.0)

CTON ships with a schema DSL for validation inside your LLM pipeline.

```ruby
schema = Cton.schema do
  object do
    key "user" do
      object do
        key "id", integer
        key "name", string
        optional "role", enum("admin", "viewer")
      end
    end
    key "tags", array(of: string)
  end
end

result = Cton.validate_schema(payload, schema)
puts result.valid? # true/false
```

Schema files can be used from the CLI as well:

```ruby
# schema.rb
CTON_SCHEMA = Cton.schema do
  object do
    key "user", object { key "id", integer }
  end
end
```

```bash
cton --schema schema.rb input.cton
```

---

## Streaming IO (1.0.0)

Handle newline-delimited CTON streams efficiently:

```ruby
io = File.open("events.cton", "r")
Cton.load_stream(io).each do |event|
  # process event
end
```

```ruby
io = File.open("events.cton", "w")
Cton.dump_stream(events, io)
```

---

## CTON-B (Binary Mode)

CTON-B is an optional binary envelope for compact transport (with optional compression):

```ruby
binary = Cton.dump_binary(payload)
round_trip = Cton.load_binary(binary)
```

CLI:

```bash
cton --to-binary input.json > output.ctonb
cton --from-binary output.ctonb
```

Note: `--stream` with binary assumes newline-delimited binary frames.

---

## Performance & Benchmarks

CTON focuses on throughput: memoized table schemas, low-allocation scalar streams, and fast boundary detection for inline docs.

Run benchmarks:

```bash
bundle exec ruby bench/encode_decode_bench.rb
ITERATIONS=2000 STREAM_SIZE=400 bundle exec ruby bench/encode_decode_bench.rb
```

---

## CLI Reference

```bash
cton [input]                 # auto-detect JSON/CTON
cton --to-json input.cton     # CTON → JSON
cton --to-cton input.json     # JSON → CTON
cton --to-binary input.json   # JSON → CTON-B
cton --from-binary input.ctonb
cton --minify input.json      # no separators
cton --pretty input.json
cton --stream input.ndjson
cton --schema schema.rb input.cton
```

---

## Development

```bash
bin/setup        # install dependencies
bundle exec rake # run tests and rubocop
bin/console      # interactive playground
```

---

## Contributing

Bug reports and pull requests are welcome at https://github.com/davidesantangelo/cton. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT © [Davide Santangelo](https://github.com/davidesantangelo)
