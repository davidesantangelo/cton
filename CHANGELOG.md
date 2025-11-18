# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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