# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-11-20

### Added

- **Performance tunables**: `Cton.dump` now accepts `decimal_mode: :fast | :precise`, allowing callers to trade float-format determinism for lower allocation pressure. Specs cover both modes.
- **Benchmark harness**: New `bench/encode_decode_bench.rb` script (wired into the README/Development docs) exercises encode/decode hot paths and prints comparative JSON vs CTON timings. On Ruby 3.1.4/macOS the fast encoder completes 1,000 iterations in ~0.63s and the new inline decoder stress test wraps 400 concatenated documents in ~4.14s.
- **Regression tests**: Added specs for streaming documents without separators plus validation around the new decimal mode toggle.

### Changed

- **Encoder**: Memoizes table schemas per array instance, adds a fast-path for homogeneous scalar lists, and reduces float/BigDecimal copying by favoring Ruby's native float formatting before falling back to `BigDecimal`. Unsupported `decimal_mode` values now raise immediately.
- **Decoder**: Replaces high-allocation `StringScanner` tokenization with raw string slicing, improves key-boundary detection for inline payloads, and keeps symbolization logic untouched. Boundary heuristics now prefer alphabetic key starts to avoid splitting numeric payloads.
- **Documentation**: README now calls out the tuning flags, inline caveats, and benchmark instructions; Development workflow highlights how to rerun the perf suite.

### Fixed

- **Inline parsing**: Eliminated the runaway allocations and incorrect key splits when processing long documents with `separator: ""`.
- **Float normalization**: Restored canonical `9.2`-style output in fast mode while keeping the new perf optimizations.

## [0.2.0] - 2025-11-19

### Added

- **CLI Tool**: New `bin/cton` executable for converting between JSON and CTON from the command line. Supports auto-detection, pretty printing, and file I/O.
- **Streaming IO**: `Cton.dump` now accepts an `IO` object as the second argument (or via `io:` keyword), allowing direct writing to files or sockets without intermediate string allocation.
- **Pretty Printing**: Added `pretty: true` option to `Cton.dump` to format output with indentation and newlines for better readability.
- **Extended Types**: Native support for `Time`, `Date` (ISO8601), `Set` (as Array), and `OpenStruct` (as Object).
- **Enhanced Error Reporting**: `ParseError` now includes line and column numbers to help locate syntax errors in large documents.

### Changed

- **Ruby 3 Compatibility**: Improved argument handling in `Cton.dump` to robustly support Ruby 3 keyword arguments when passing hashes.

## [0.1.1] - 2025-11-18

### Changed

- **Performance**: Refactored `Encoder` to use `StringIO` and `Decoder` to use `StringScanner` for significantly improved performance and memory usage.
- **Architecture**: Split `Cton` module into dedicated `Cton::Encoder` and `Cton::Decoder` classes for better maintainability.

### Fixed

- **Parsing**: Fixed an issue where unterminated strings were not correctly detected.
- **Whitespace**: Improved whitespace handling in the decoder, specifically fixing issues with whitespace between keys and structure markers.

### Added

- **Type Safety**: Added comprehensive RBS signatures (`sig/cton.rbs`) for better IDE support and static analysis.
- **Tests**: Expanded test coverage for validation, complex tables, mixed arrays, unicode values, and error cases.

## [0.1.0] - 2025-11-18

### Added

- **Initial Release**: First public version of the `cton` gem.
- **CTON Encoder**: `Cton.dump` (aliased as `Cton.generate`) to convert a Ruby `Hash` into a CTON string.
  - Encodes objects, arrays, strings, numbers, booleans, and `nil`.
  - Automatic table detection for arrays of uniform hashes, creating a highly compact representation: `key[N]{h1,h2}=v1,v2;...`.
  - Smart string quoting: only quotes strings containing special characters, whitespace, or those that could be misinterpreted as numbers, booleans, or null.
  - Number normalization: canonicalizes floats and `BigDecimal` to a clean, exponent-free format. `NaN` and `Infinity` are converted to `null` for safety.
  - Configurable separator (`\n` by default) between top-level key-value pairs.
- **CTON Decoder**: `Cton.load` (aliased as `Cton.parse`) to parse a CTON string back into a Ruby object.
  - Handles all CTON structures: objects `()`, arrays `[]`, and compact tables `[]{}`.
  - Supports an optional `symbolize_names: true` argument to convert all hash keys to symbols.
  - Robust parsing of scalars, including quoted and unquoted strings.
- **Error Handling**: `Cton::EncodeError` for unsupported Ruby types during encoding and `Cton::ParseError` for malformed CTON input.
- **Documentation**: `README.md` with a format overview, usage examples, and rationale.
- **Testing**: Comprehensive RSpec suite ensuring round-trip integrity and correct handling of edge cases.