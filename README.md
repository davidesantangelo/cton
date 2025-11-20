# CTON

[![Gem Version](https://badge.fury.io/rb/cton.svg)](https://badge.fury.io/rb/cton)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/davidesantangelo/cton/blob/master/LICENSE.txt)

**CTON** (Compact Token-Oriented Notation) is an aggressively minified, JSON-compatible wire format that keeps prompts short without giving up schema hints. It is shape-preserving (objects, arrays, scalars, table-like arrays) and deterministic, so you can safely round-trip between Ruby hashes and compact strings that work well in LLM prompts.

---

## 📖 Table of Contents

- [What is CTON?](#what-is-cton)
- [Why another format?](#why-another-format)
- [Examples](#examples)
- [Token Savings](#token-savings-vs-json--toon)
- [Installation](#installation)
- [Usage](#usage)
- [Performance & Benchmarks](#performance--benchmarks)
- [Teaching CTON to LLMs](#teaching-cton-to-llms)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

---

## What is CTON?

CTON is designed to be the most efficient way to represent structured data for Large Language Models (LLMs). It strips away the "syntactic sugar" of JSON that humans like (indentation, excessive quoting, braces) but machines don't strictly need, while adding "structural hints" that help LLMs generate valid output.

### Key Concepts

1.  **Root is Implicit**: No curly braces `{}` wrapping the entire document.
2.  **Minimal Punctuation**:
    *   Objects use `key=value`.
    *   Nested objects use parentheses `(key=value)`.
    *   Arrays use brackets with length `[N]=item1,item2`.
3.  **Table Compression**: If an array contains objects with the same keys, CTON automatically converts it into a table format `[N]{header1,header2}=val1,val2;val3,val4`. This is a massive token saver for datasets.

---

## Examples

### Simple Key-Value Pairs

**JSON**
```json
{
  "task": "planning",
  "urgent": true,
  "id": 123
}
```

**CTON**
```text
task=planning,urgent=true,id=123
```

### Nested Objects

**JSON**
```json
{
  "user": {
    "name": "Davide",
    "settings": {
      "theme": "dark"
    }
  }
}
```

**CTON**
```text
user(name=Davide,settings(theme=dark))
```

### Arrays and Tables

**JSON**
```json
{
  "tags": ["ruby", "gem", "llm"],
  "files": [
    { "name": "README.md", "size": 1024 },
    { "name": "lib/cton.rb", "size": 2048 }
  ]
}
```

**CTON**
```text
tags[3]=ruby,gem,llm
files[2]{name,size}=README.md,1024;lib/cton.rb,2048
```

---

## Why another format?

- **Less noise than YAML/JSON**: no indentation, no braces around the root, and optional quoting.
- **Schema guardrails**: arrays carry their length (`friends[3]`) and table headers (`{id,name,...}`) so downstream parsing can verify shape.
- **LLM-friendly**: works as a single string you can embed in a prompt together with short parsing instructions.
- **Token savings**: CTON compounds the JSON → TOON savings.

### Token savings vs JSON & TOON

- **JSON → TOON**: The [TOON benchmarks](https://toonformat.dev) report roughly 40% fewer tokens than plain JSON on mixed-structure prompts while retaining accuracy due to explicit array lengths and headers.
- **TOON → CTON**: By stripping indentation and forcing everything inline, CTON cuts another ~20–40% of characters.
- **Net effect**: In practice you can often reclaim **50–60% of the token budget** versus raw JSON, leaving more room for instructions or reasoning steps while keeping a deterministic schema.

---

## Installation

Add the gem to your application:

```bash
bundle add cton
```

Or install it directly:

```bash
gem install cton
```

---

## Usage

```ruby
require "cton"

payload = {
  "context" => {
    "task" => "Our favorite hikes together",
    "location" => "Boulder",
    "season" => "spring_2025"
  },
  "friends" => %w[ana luis sam],
  "hikes" => [
    { "id" => 1, "name" => "Blue Lake Trail", "distanceKm" => 7.5, "elevationGain" => 320, "companion" => "ana", "wasSunny" => true },
    { "id" => 2, "name" => "Ridge Overlook", "distanceKm" => 9.2, "elevationGain" => 540, "companion" => "luis", "wasSunny" => false },
    { "id" => 3, "name" => "Wildflower Loop", "distanceKm" => 5.1, "elevationGain" => 180, "companion" => "sam", "wasSunny" => true }
  ]
}

# Encode to CTON
cton = Cton.dump(payload)
# => "context(... )\nfriends[3]=ana,luis,sam\nhikes[3]{...}"

# Decode back to Hash
round_tripped = Cton.load(cton)
# => original hash

# Need symbols?
symbolized = Cton.load(cton, symbolize_names: true)

# Want a truly inline document? Opt in explicitly (decoding becomes unsafe for ambiguous cases).
inline = Cton.dump(payload, separator: "")

# Pretty print for human readability
pretty = Cton.dump(payload, pretty: true)

# Stream to an IO object (file, socket, etc.)
File.open("data.cton", "w") do |f|
  Cton.dump(payload, f)
end

# Toggle float normalization strategies
fast  = Cton.dump(payload) # default :fast mode
strict = Cton.dump(payload, decimal_mode: :precise)
```

### CLI Tool

CTON comes with a command-line tool for quick conversions:

```bash
# Convert JSON to CTON
echo '{"hello": "world"}' | cton
# => hello=world

# Convert CTON to JSON
echo 'hello=world' | cton --to-json
# => {"hello":"world"}

# Pretty print
cton --pretty input.json
```

### Advanced Features

#### Extended Types
CTON natively supports serialization for:
- `Time` and `Date` (ISO8601 strings)
- `Set` (converted to Arrays)
- `OpenStruct` (converted to Objects)

#### Table detection
Whenever an array is made of hashes that all expose the same scalar keys, the encoder flattens it into a table to save tokens. Mixed or nested arrays fall back to `[N]=(value1,value2,...)`.

#### Separators & ambiguity
Removing every newline makes certain inputs ambiguous because `sam` and the next key `hikes` can merge into `samhikes`. The default `separator: "\n"` avoids that by inserting a single newline between root segments. You may pass `separator: ""` to `Cton.dump` for maximum compactness, but decoding such strings is only safe if you can guarantee extra quoting or whitespace between segments. When you intentionally omit separators, keep next-level keys alphabetic (e.g., `payload`, `k42`) so the decoder's boundary heuristic can split `...1payload...` without misclassifying numeric prefixes.

#### Literal safety & number normalization
Following the TOON specification's guardrails, the encoder now:
- Auto-quotes strings that would otherwise be parsed as booleans, `null`, or numbers (e.g., `"true"`, `"007"`, `"1e6"`, `"-5"`) so they round-trip as strings without extra work.
- Canonicalizes float/BigDecimal output: no exponent notation, no trailing zeros, and `-0` collapses to `0`.
- Converts `NaN` and `±Infinity` inputs to `null`, matching TOON's normalization guidance so downstream decoders don't explode on non-finite numbers.

#### Decimal normalization modes
- `decimal_mode: :fast` (default) prefers Ruby's native float representation and only falls back to `BigDecimal` when scientific notation is detected, minimizing allocations on tight loops.
- `decimal_mode: :precise` forces the legacy `BigDecimal` path for every float, which is slower but useful for audit-grade dumps where you want deterministic decimal expansion.
- Both modes share the same trailing-zero stripping and `-0 → 0` normalization, so switching modes never affects integer formatting.

---

## Performance & Benchmarks

CTON focuses on throughput: encoder table schemas are memoized, scalar list encoding keeps a reusable buffer, floats avoid `BigDecimal` when they can, and the decoder slices straight from the raw string to sidestep `StringScanner` allocations. You can reproduce the numbers below with the bundled script:

```bash
bundle exec ruby bench/encode_decode_bench.rb
# customize input size / iterations
ITERATIONS=2000 STREAM_SIZE=400 bundle exec ruby bench/encode_decode_bench.rb
```

Latest results on Ruby 3.1.4/macOS (M-series), 1,000 iterations, `STREAM_SIZE=200`:

| Benchmark | Time (s) |
| --- | --- |
| `cton dump` (:fast) | 0.626 |
| `cton dump` (:precise) | 0.658 |
| `json generate` | 0.027 |
| `cton load` | 2.067 |
| `json parse` | 0.045 |
| `cton inline load` (separator=`""`, double payload) | 4.140 |

`cton inline load` deliberately concatenates documents without separators to stress the new boundary detector; it now finishes without the runaway allocations seen in earlier releases.

---

## Teaching CTON to LLMs

Use this system prompt to teach an LLM how to understand and generate CTON:

````markdown
You are an expert in data serialization and specifically in CTON (Compact Token-Oriented Notation). CTON is a token-efficient data format optimized for LLMs that serves as a compact alternative to JSON.

Your task is to interpret CTON input and convert it to JSON, or convert JSON input into valid CTON format, following the specification below.

### CTON Specification

CTON minimizes syntax characters (braces, quotes) while preserving structure and type safety.

**1. Basic Structure (Key-Value)**
- **Rule:** Do not use outer curly braces `{}` for the root object.
- **Rule:** Use `=` to separate keys and values.
- **Rule:** Use `,` to separate fields.
- **Rule:** Do not use quotes around "safe" strings (alphanumeric, simple text).
- **Example:** - JSON: `{"task": "planning", "urgent": true}`
  - CTON: `task=planning,urgent=true`

**2. Nested Objects**
- **Rule:** Use parentheses `()` to denote a nested object instead of `{}`.
- **Example:**
  - JSON: `{"context": {"user": "Davide", "theme": "dark"}}`
  - CTON: `context(user=Davide,theme=dark)`

**3. Arrays of Objects (Table Compression)**
- **Rule:** Use the syntax `key[count]{columns}=values` for arrays of objects to avoid repeating keys.
- **Structure:** `key[Length]{col1,col2}=val1,val2;val1,val2`
- **Details:** - `[N]` denotes the number of items in the array.
  - `{col1,col2}` defines the schema headers.
  - `;` separates distinct objects (rows).
  - `,` separates values within an object.
- **Example:**

JSON:
```json
{
  "files": [
    { "name": "README.md", "size": 1024 },
    { "name": "lib.rb", "size": 2048 }
  ]
}
```

CTON: `files[2]{name,size}=README.md,1024;lib.rb,2048`

**4. Type Safety & Literals**
- **Booleans/Null:** `true`, `false`, and `null` are preserved as literals (unquoted).
- **Numbers:** Integers and floats are written as is (e.g., `1024`, `3.14`).
- **Escaping:** If a string value looks like a boolean, number, or contains reserved characters (like `,`, `;`, `=`, `(`, `)`), it must be wrapped in double quotes (e.g., `"true"`).

### Examples for Training

**Input (JSON):**
```json
{
  "id": 123,
  "active": true,
  "metadata": {
    "created_at": "2023-01-01",
    "tags": "admin"
  }
}
```
````

---

## Type Safety

CTON ships with RBS signatures (`sig/cton.rbs`) to support type checking and IDE autocompletion.

## Development

```bash
bin/setup        # install dependencies
bundle exec rake # run tests and rubocop
bin/console      # interactive playground
bundle exec ruby bench/encode_decode_bench.rb # performance smoke test
```

To release a new version, bump `Cton::VERSION` and run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/davidesantangelo/cton. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT © [Davide Santangelo](https://github.com/davidesantangelo)
