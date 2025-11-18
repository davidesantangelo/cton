````markdown
# CTON

CTON (Compact Token-Oriented Notation) is an aggressively minified, JSON-compatible wire format that keeps prompts short without giving up schema hints. It is shape-preserving (objects, arrays, scalars, table-like arrays) and deterministic, so you can safely round-trip between Ruby hashes and compact strings that work well in LLM prompts.

## Why another format?

- **Less noise than YAML/JSON**: no indentation, no braces around the root, and optional quoting.
- **Schema guardrails**: arrays carry their length (`friends[3]`) and table headers (`{id,name,...}`) so downstream parsing can verify shape.
- **LLM-friendly**: works as a single string you can embed in a prompt together with short parsing instructions.
- **Token savings**: CTON compounds the JSON → TOON savings; see the section below for concrete numbers.

## Token savings vs JSON & TOON

- **JSON → TOON**: The [TOON benchmarks](https://toonformat.dev) report roughly 40% fewer tokens than plain JSON on mixed-structure prompts while retaining accuracy due to explicit array lengths and headers.
- **TOON → CTON**: By stripping indentation and forcing everything inline, CTON cuts another ~20–40% of characters. The sample above is ~350 characters as TOON and ~250 as CTON (~29% fewer), and larger tabular datasets show similar reductions.
- **Net effect**: In practice you can often reclaim 50–60% of the token budget versus raw JSON, leaving more room for instructions or reasoning steps while keeping a deterministic schema.

## Format at a glance

```
context(task="Our favorite hikes together",location=Boulder,season=spring_2025)
friends[3]=ana,luis,sam
hikes[3]{id,name,distanceKm,elevationGain,companion,wasSunny}=1,"Blue Lake Trail",7.5,320,ana,true;2,"Ridge Overlook",9.2,540,luis,false;3,"Wildflower Loop",5.1,180,sam,true
```

- Objects use parentheses and `key=value` pairs separated by commas.
- Arrays encode their length: `[N]=...`. When every element is a flat hash with the same keys, they collapse into a compact table: `[N]{key1,key2}=row1;row2`.
- Scalars (numbers, booleans, `null`) keep their JSON text. Strings only need quotes when they contain whitespace or reserved punctuation.
- For parsing safety the Ruby encoder inserts a single `\n` between top-level segments. You can override this if you truly need a fully inline document (see options below).

## Installation

Add the gem to your application:

```bash
bundle add cton
```

Or install it directly:

```bash
gem install cton
```

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

cton = Cton.dump(payload)
# => "context(... )\nfriends[3]=ana,luis,sam\nhikes[3]{...}"

round_tripped = Cton.load(cton)
# => original hash

# Need symbols?
symbolized = Cton.load(cton, symbolize_names: true)

# Want a truly inline document? Opt in explicitly (decoding becomes unsafe for ambiguous cases).
inline = Cton.dump(payload, separator: "")
```

### Table detection

Whenever an array is made of hashes that all expose the same scalar keys, the encoder flattens it into a table to save tokens. Mixed or nested arrays fall back to `[N]=(value1,value2,...)`.

### Separators & ambiguity

Removing every newline makes certain inputs ambiguous because `sam` and the next key `hikes` can merge into `samhikes`. The default `separator: "\n"` avoids that by inserting a single newline between root segments. You may pass `separator: ""` to `Cton.dump` for maximum compactness, but decoding such strings is only safe if you can guarantee extra quoting or whitespace between segments.

### Literal safety & number normalization

Following the TOON specification's guardrails, the encoder now:

- Auto-quotes strings that would otherwise be parsed as booleans, `null`, or numbers (e.g., `"true"`, `"007"`, `"1e6"`, `"-5"`) so they round-trip as strings without extra work.
- Canonicalizes float/BigDecimal output: no exponent notation, no trailing zeros, and `-0` collapses to `0`.
- Converts `NaN` and `±Infinity` inputs to `null`, matching TOON's normalization guidance so downstream decoders don't explode on non-finite numbers.

## Development

```bash
bin/setup   # install dependencies
bundle exec rspec
bin/console # interactive playground
```

To release a new version, bump `Cton::VERSION` and run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/davidesantangelo/cton. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT © Davide Santangelo
````
