# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Cton do
  let(:sample_data) do
    {
      "context" => {
        "task" => "Our favorite hikes together",
        "location" => "Boulder",
        "season" => "spring_2025"
      },
      "friends" => %w[ana luis sam],
      "hikes" => [
        { "id" => 1, "name" => "Blue Lake Trail", "distanceKm" => 7.5, "elevationGain" => 320, "companion" => "ana",
          "wasSunny" => true },
        { "id" => 2, "name" => "Ridge Overlook", "distanceKm" => 9.2, "elevationGain" => 540, "companion" => "luis",
          "wasSunny" => false },
        { "id" => 3, "name" => "Wildflower Loop", "distanceKm" => 5.1, "elevationGain" => 180, "companion" => "sam",
          "wasSunny" => true }
      ]
    }
  end

  let(:sample_cton) do
    [
      'context(task="Our favorite hikes together",location=Boulder,season=spring_2025)',
      "friends[3]=ana,luis,sam",
      'hikes[3]{id,name,distanceKm,elevationGain,companion,wasSunny}=1,"Blue Lake Trail",7.5,320,ana,true;2,"Ridge Overlook",9.2,540,luis,false;3,"Wildflower Loop",5.1,180,sam,true'
    ].join("\n")
  end

  let(:inline_cton) { sample_cton.delete("\n") }

  describe ".dump" do
    context "core behavior" do
      it "encodes Ruby data into compact CTON" do
        expect(Cton.dump(sample_data)).to eq(sample_cton)
      end

      it "can emit inline strings when requested" do
        expect(Cton.dump(sample_data, separator: "")).to eq(inline_cton)
      end

      it "raises when encountering unsupported types" do
        expect { Cton.dump("value" => Object.new) }.to raise_error(Cton::EncodeError)
      end
    end

    context "edge cases" do
      it "encodes empty structures and nulls" do
        payload = {
          "empty_object" => {},
          "empty_array" => [],
          "nil_value" => nil
        }

        expect(Cton.dump(payload)).to eq([
          "empty_object()",
          "empty_array[0]=",
          "nil_value=null"
        ].join("\n"))
      end

      it "quotes strings requiring escapes" do
        payload = {
          "note" => "comma, newline\nquote\" tab\t"
        }

        expect(Cton.dump(payload)).to eq('note="comma, newline\nquote\" tab\t"')
      end

      it "quotes literal-looking strings to preserve types" do
        payload = {
          "bool_string" => "true",
          "numeric_string" => "007",
          "float_like" => "1e6",
          "negative_digits" => "-5"
        }

        encoded = Cton.dump(payload)

        expect(encoded).to eq([
          'bool_string="true"',
          'numeric_string="007"',
          'float_like="1e6"',
          'negative_digits="-5"'
        ].join("\n"))

        expect(Cton.load(encoded)).to eq(payload)
      end

      it "supports BigDecimal serialization" do
        payload = { "price" => BigDecimal("12.3400") }
        expect(Cton.dump(payload)).to eq("price=12.34")
      end
    end

    context "number normalization" do
      it "canonicalizes float output" do
        payload = {
          "intish" => 1.0,
          "fraction" => 0.5,
          "scientific" => 1.2e6,
          "negative_zero" => -0.0
        }

        expect(Cton.dump(payload)).to eq([
          "intish=1",
          "fraction=0.5",
          "scientific=1200000",
          "negative_zero=0"
        ].join("\n"))
      end

      it "converts non-finite floats to null" do
        payload = {
          "pos_inf" => Float::INFINITY,
          "neg_inf" => -Float::INFINITY,
          "not_a_number" => Float::NAN
        }

        expect(Cton.dump(payload)).to eq([
          "pos_inf=null",
          "neg_inf=null",
          "not_a_number=null"
        ].join("\n"))
      end

      it "trims trailing zeros in BigDecimal output" do
        payload = { "precise" => BigDecimal("123.4500") }
        expect(Cton.dump(payload)).to eq("precise=123.45")
      end
    end

    context "performance tunables" do
      it "allows opting into precise decimal mode" do
        payload = { "value" => 0.125 }
        expect(Cton.dump(payload, decimal_mode: :precise)).to eq("value=0.125")
      end

      it "rejects unknown decimal modes" do
        expect { Cton.dump({ "a" => 1 }, decimal_mode: :unknown) }.to raise_error(ArgumentError)
      end
    end

    context "table detection" do
      it "compacts uniform scalar hashes" do
        payload = {
          "rows" => [
            { "a" => 1, "b" => 2 },
            { "a" => 3, "b" => 4 }
          ]
        }

        expect(Cton.dump(payload)).to eq("rows[2]{a,b}=1,2;3,4")
      end

      it "leaves heterogeneous arrays as nested objects" do
        payload = {
          "rows" => [
            { "a" => 1 },
            { "b" => 2 }
          ]
        }

        expect(Cton.dump(payload)).to eq("rows[2]=(a=1),(b=2)")
      end
    end
  end

  describe ".load" do
    context "core behavior" do
      it "decodes a CTON document" do
        expect(Cton.load(sample_cton)).to eq(sample_data)
      end

      it "symbolizes keys on request" do
        parsed = Cton.load(sample_cton, symbolize_names: true)
        expect(parsed[:context][:task]).to eq("Our favorite hikes together")
        expect(parsed[:hikes].first[:wasSunny]).to be(true)
      end

      it "parses nested arrays and objects" do
        cton = "payload(meta=(count=2,flags=[2]=true,false),items=[2]=(id=1,details=(notes=[2]=alpha,beta)),(id=2,details=(notes=[0]=)))"
        parsed = Cton.load(cton)

        expect(parsed).to eq(
          "payload" => {
            "meta" => { "count" => 2, "flags" => [true, false] },
            "items" => [
              { "id" => 1, "details" => { "notes" => %w[alpha beta] } },
              { "id" => 2, "details" => { "notes" => [] } }
            ]
          }
        )
      end

      it "parses inline documents when callers add manual separators" do
        inline = "alpha(value=1) beta[2]=true,false gamma()"
        expect(Cton.load(inline)).to eq(
          "alpha" => { "value" => 1 },
          "beta" => [true, false],
          "gamma" => {}
        )
      end

      it "parses long inline documents without separators" do
        payload = (1..200).each_with_object({}) do |index, memo|
          memo["k#{index}"] = index
        end

        inline = Cton.dump(payload, separator: "")
        expect(Cton.load(inline)).to eq(payload)
      end
    end

    context "error handling" do
      it "rejects arrays with fewer values than advertised" do
        expect { Cton.load("friends[2]=ana") }.to raise_error(Cton::ParseError)
      end

      it "rejects malformed tables" do
        expect { Cton.load("rows[1]{id,name}=42") }.to raise_error(Cton::ParseError)
      end

      it "rejects unterminated strings" do
        expect { Cton.load('note="unclosed') }.to raise_error(Cton::ParseError)
      end

      it "checks for trailing garbage" do
        expect { Cton.load("context(task=1))oops") }.to raise_error(Cton::ParseError)
      end
    end
  end

  describe "round-trip guarantees" do
    it "round-trips nested payloads" do
      payload = {
        "meta" => { "count" => 2, "labels" => %w[alpha beta] },
        "items" => [
          { "id" => 1, "notes" => ["needs_review", { "priority" => "p1" }] },
          { "id" => 2, "notes" => [] }
        ],
        "flags" => [true, false, nil]
      }

      encoded = Cton.dump(payload)
      expect(Cton.load(encoded)).to eq(payload)
    end

    it "round-trips deeply nested structures" do
      payload = {
        "a" => [{ "b" => [{ "c" => (1..3).to_a }] }],
        "matrix" => [[1, 2], [3, 4]],
        "blank" => {}
      }

      encoded = Cton.dump(payload)
      expect(Cton.load(encoded)).to eq(payload)
    end
  end

  describe "extended coverage" do
    context "validation" do
      it "raises error for keys with invalid characters" do
        expect { Cton.dump("invalid key" => 1) }.to raise_error(Cton::EncodeError)
        expect { Cton.dump("key!" => 1) }.to raise_error(Cton::EncodeError)
      end

      it "raises error for keys with unicode characters" do
        expect { Cton.dump("héllo" => 1) }.to raise_error(Cton::EncodeError)
      end
    end

    context "complex tables" do
      it "handles tables with values needing quoting" do
        data = {
          "users" => [
            { "name" => "Doe, John", "bio" => "A;B" },
            { "name" => "Smith, Jane", "bio" => "C,D" }
          ]
        }
        encoded = Cton.dump(data)
        expect(encoded).to include('users[2]{name,bio}="Doe, John","A;B";"Smith, Jane","C,D"')
        expect(Cton.load(encoded)).to eq(data)
      end

      it "falls back to object list if hash keys are unordered" do
        data = {
          "items" => [
            { "a" => 1, "b" => 2 },
            { "b" => 4, "a" => 3 }
          ]
        }
        # Keys are different ([a,b] vs [b,a]), so not a table candidate
        encoded = Cton.dump(data)
        expect(encoded).to include("items[2]=(a=1,b=2),(b=4,a=3)")
        expect(Cton.load(encoded)).to eq(data)
      end
    end

    context "mixed arrays" do
      it "handles arrays with mixed types" do
        data = {
          "mixed" => [
            1,
            "string",
            { "a" => 1 },
            [1, 2],
            true,
            nil
          ]
        }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end

    context "unicode values" do
      it "correctly round-trips unicode strings" do
        data = { "message" => "Hello 🌍", "symbols" => "←↑→↓" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end

    context "whitespace handling" do
      it "parses with excessive whitespace" do
        cton = <<~CTON
          user (
            name = "John" ,
            age = 30
          )
        CTON
        expect(Cton.load(cton)).to eq({ "user" => { "name" => "John", "age" => 30 } })
      end
    end

    context "additional error cases" do
      it "raises on missing value after assignment" do
        expect { Cton.load("key=") }.to raise_error(Cton::ParseError)
      end

      it "raises on incomplete array" do
        expect { Cton.load("arr[2]=1") }.to raise_error(Cton::ParseError)
      end

      it "raises on invalid array length" do
        expect { Cton.load("arr[a]=1") }.to raise_error(Cton::ParseError)
      end
    end
  end

  describe "pretty printing" do
    context "output formatting" do
      it "formats output with indentation" do
        data = { "user" => { "name" => "Davide", "age" => 30 } }
        expected = <<~CTON.chomp
          user(
            name=Davide,
            age=30
          )
        CTON
        expect(Cton.dump(data, pretty: true)).to eq(expected)
      end

      it "formats tables with indentation" do
        data = { "users" => [{ "name" => "A" }, { "name" => "B" }] }
        expected = <<~CTON
          users[2]{name}=
            A;
            B
        CTON
        expect(Cton.dump(data, pretty: true)).to eq(expected)
      end
    end
  end

  describe "streaming IO" do
    context "IO output" do
      it "writes to an IO object" do
        io = StringIO.new
        Cton.dump({ "a" => 1 }, io)
        expect(io.string).to eq("a=1")
      end

      it "supports IO as a keyword argument" do
        io = StringIO.new
        Cton.dump({ "a" => 1 }, io: io)
        expect(io.string).to eq("a=1")
      end
    end
  end

  describe "extended types" do
    context "type serialization" do
      it "serializes Time as ISO8601 string" do
        time = Time.utc(2025, 11, 19, 12, 0, 0)
        expect(Cton.dump("t" => time)).to eq("t=2025-11-19T12:00:00Z")
      end

      it "serializes Date as ISO8601 string" do
        date = Date.new(2025, 11, 19)
        expect(Cton.dump("d" => date)).to eq("d=2025-11-19")
      end

      it "serializes Set as Array" do
        require "set"
        set = Set.new([1, 2])
        expect(Cton.dump("s" => set)).to eq("s[2]=1,2")
      end

      it "serializes OpenStruct as Object" do
        require "ostruct"
        os = OpenStruct.new(a: 1)
        expect(Cton.dump("o" => os)).to eq("o(a=1)")
      end
    end
  end

  describe "error reporting" do
    context "parse error details" do
      it "reports line and column number on error" do
        cton = "key=value\nkey2=\"unclosed"
        expect { Cton.load(cton) }.to raise_error(Cton::ParseError, /at line 2/)
      end
    end
  end

  describe "comment support" do
    context "comment support" do
      it "ignores single-line comments in CTON" do
        cton = <<~CTON
          # This is a comment
          name=Alice
          # Another comment
          age=30
        CTON
        expect(Cton.load(cton)).to eq({ "name" => "Alice", "age" => 30 })
      end

      it "ignores inline comments" do
        cton = "name=Alice # this is a comment\nage=30"
        expect(Cton.load(cton)).to eq({ "name" => "Alice", "age" => 30 })
      end

      it "handles comments in objects" do
        cton = <<~CTON
          user(
            # User's name
            name=Davide,
            # User's age
            age=30
          )
        CTON
        expect(Cton.load(cton)).to eq({ "user" => { "name" => "Davide", "age" => 30 } })
      end

      it "emits comments when provided via comments option" do
        data = { "context" => { "task" => "test" }, "items" => [1, 2] }
        comments = {
          "context" => "Configuration context",
          "items" => "List of items"
        }
        encoded = Cton.dump(data, comments: comments)
        expect(encoded).to include("# Configuration context")
        expect(encoded).to include("# List of items")
      end

      it "round-trips data with comments" do
        data = { "name" => "Alice", "age" => 30 }
        comments = { "name" => "User name" }
        encoded = Cton.dump(data, comments: comments)
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "validation API" do
    context ".valid?" do
      describe "validity checks" do
        it "returns true for valid CTON" do
          expect(Cton.valid?("key=value")).to be true
          expect(Cton.valid?("user(name=Alice,age=30)")).to be true
          expect(Cton.valid?("items[3]=1,2,3")).to be true
        end

        it "returns false for invalid CTON" do
          expect(Cton.valid?("key=(broken")).to be false
          expect(Cton.valid?('note="unclosed')).to be false
        end
      end
    end

    context ".validate" do
      describe "validation results" do
        it "returns ValidationResult object" do
          result = Cton.validate("key=value")
          expect(result).to be_a(Cton::ValidationResult)
          expect(result.valid?).to be true
          expect(result.errors).to be_empty
        end

        it "captures validation errors with location" do
          result = Cton.validate("key=(broken")
          expect(result.valid?).to be false
          expect(result.errors).not_to be_empty

          error = result.errors.first
          expect(error.line).to be_a(Integer)
          expect(error.column).to be_a(Integer)
          expect(error.message).to be_a(String)
        end

        it "detects unterminated strings" do
          result = Cton.validate('note="unclosed')
          expect(result.valid?).to be false
          expect(result.errors.first.message).to include("Unterminated")
        end

        it "returns string representation" do
          result = Cton.validate("key=value")
          expect(result.to_s).to include("Valid")

          result = Cton.validate("key=(broken")
          expect(result.to_s).to include("Invalid")
        end
      end
    end
  end

  describe "token statistics" do
    context ".stats" do
      describe "statistics calculations" do
        let(:data) { { "name" => "Alice", "items" => [1, 2, 3] } }

        it "returns Stats object" do
          stats = Cton.stats(data)
          expect(stats).to be_a(Cton::Stats)
        end

        it "calculates JSON and CTON sizes" do
          stats = Cton.stats(data)
          expect(stats.json_chars).to be > 0
          expect(stats.cton_chars).to be > 0
          expect(stats.cton_chars).to be < stats.json_chars
        end

        it "calculates savings percentage" do
          stats = Cton.stats(data)
          expect(stats.savings_percent).to be > 0
          expect(stats.savings_percent).to be < 100
        end

        it "estimates token counts" do
          stats = Cton.stats(data)
          expect(stats.estimated_json_tokens).to be > 0
          expect(stats.estimated_cton_tokens).to be > 0
          expect(stats.estimated_token_savings).to be > 0
        end

        it "returns hash representation" do
          stats = Cton.stats(data)
          hash = stats.to_h
          expect(hash).to include(:json_chars, :cton_chars, :savings_percent, :estimated_tokens)
        end

        it "returns string representation" do
          stats = Cton.stats(data)
          str = stats.to_s
          expect(str).to include("JSON:")
          expect(str).to include("CTON:")
          expect(str).to include("Saved:")
        end
      end
    end

    context ".stats_hash" do
      describe "hash output" do
        it "returns hash directly" do
          data = { "test" => "value" }
          hash = Cton.stats_hash(data)
          expect(hash).to be_a(Hash)
          expect(hash[:json_chars]).to be > 0
        end
      end
    end

    context "Stats.compare" do
      describe "format comparison" do
        it "compares multiple format variants" do
          data = { "name" => "test", "values" => [1, 2, 3] }
          comparison = Cton::Stats.compare(data)

          expect(comparison).to include(:cton, :cton_inline, :cton_pretty, :json, :json_pretty)
          expect(comparison[:cton][:cton_chars]).to be < comparison[:json][:chars]
        end
      end
    end
  end

  describe "custom type registry" do
    context "type handlers" do
      # Define a simple test class
      let(:money_class) do
        Class.new do
          attr_reader :cents, :currency

          def initialize(cents, currency)
            @cents = cents
            @currency = currency
          end
        end
      end

      after do
        Cton.clear_type_registry!
      end

      describe "registration" do
        it "registers a custom type handler" do
          Cton.register_type(money_class) do |money|
            { amount: money.cents, currency: money.currency }
          end

          money = money_class.new(1999, "USD")
          encoded = Cton.dump({ "price" => money })
          expect(encoded).to include("price(amount=1999,currency=USD)")
        end

        it "supports scalar mode" do
          uuid_class = Class.new do
            def initialize(value)
              @value = value
            end

            def to_s
              @value
            end
          end

          Cton.register_type(uuid_class, as: :scalar, &:to_s)

          uuid = uuid_class.new("abc-123-def")
          encoded = Cton.dump({ "id" => uuid })
          expect(encoded).to eq("id=abc-123-def")
        end

        it "supports array mode" do
          range_class = Class.new do
            def initialize(min, max)
              @min = min
              @max = max
            end

            def to_a
              [@min, @max]
            end
          end

          Cton.register_type(range_class, as: :array, &:to_a)

          range = range_class.new(1, 10)
          encoded = Cton.dump({ "range" => range })
          expect(encoded).to eq("range[2]=1,10")
        end
      end

      describe "unregistration" do
        it "removes a registered handler" do
          Cton.register_type(money_class) { |m| { cents: m.cents } }
          Cton.unregister_type(money_class)

          money = money_class.new(100, "USD")
          expect { Cton.dump({ "price" => money }) }.to raise_error(Cton::EncodeError)
        end
      end

      describe "registry access" do
        it "provides access to the registry" do
          expect(Cton.type_registry).to be_a(Cton::TypeRegistry)
        end

        it "tracks registered types" do
          Cton.register_type(money_class) { |m| { cents: m.cents } }
          expect(Cton.type_registry.registered_types).to include(money_class)
        end
      end
    end
  end

  describe "structured errors" do
    context "ParseError attributes" do
      it "includes line and column in ParseError" do
        Cton.load("key=(broken")
      rescue Cton::ParseError => e
        expect(e.line).to be_a(Integer)
        expect(e.column).to be_a(Integer)
      end

      it "includes source excerpt in ParseError" do
        Cton.load("key=(broken")
      rescue Cton::ParseError => e
        expect(e.source_excerpt).to be_a(String)
      end

      it "provides to_h for structured access" do
        Cton.load("key=(broken")
      rescue Cton::ParseError => e
        hash = e.to_h
        expect(hash).to include(:message, :line, :column)
      end
    end
  end

  describe "boundary detection" do
    context "key boundary parsing" do
      it "correctly splits adjacent keys without separators" do
        cton = "a=1b=2c=3"
        expect(Cton.load(cton)).to eq({ "a" => 1, "b" => 2, "c" => 3 })
      end

      it "handles keys starting with numbers correctly" do
        cton = "k1=1k2=2k3=3"
        expect(Cton.load(cton)).to eq({ "k1" => 1, "k2" => 2, "k3" => 3 })
      end

      it "handles keys with dots and dashes" do
        data = { "api.version" => "v1", "content-type" => "json" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles underscores in keys" do
        data = { "user_id" => 123, "created_at" => "2025-01-01" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "escape sequences" do
    context "string escaping" do
      it "handles all escape sequences" do
        data = { "text" => "line1\nline2\rcarriage\ttab" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles escaped quotes" do
        data = { "quote" => 'He said "hello"' }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles escaped backslashes" do
        data = { "path" => "C:\\Users\\test" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles combined escapes" do
        data = { "complex" => "line1\\n\nline2\\t\t\"quoted\"" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "numeric edge cases" do
    context "extreme numbers" do
      it "handles very large integers" do
        data = { "big" => 999_999_999_999_999 }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles negative integers" do
        data = { "negative" => -42, "zero" => 0 }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles very small floats" do
        data = { "small" => 0.000001 }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)["small"]).to be_within(0.0000001).of(0.000001)
      end

      it "handles negative floats" do
        data = { "neg_float" => -3.14159 }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)["neg_float"]).to be_within(0.00001).of(-3.14159)
      end
    end
  end

  describe "deeply nested structures" do
    context "nesting depth" do
      it "handles 5 levels of object nesting" do
        data = { "a" => { "b" => { "c" => { "d" => { "e" => "deep" } } } } }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles nested arrays in objects" do
        data = { "matrix" => { "rows" => [[1, 2], [3, 4]], "cols" => 2 } }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles objects in arrays in objects" do
        data = { "users" => [{ "roles" => [{ "name" => "admin" }] }] }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "empty and null handling" do
    context "edge cases" do
      it "handles multiple empty structures" do
        data = { "obj" => {}, "arr" => [], "nested" => { "empty" => {} } }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles array with all nulls" do
        data = { "nulls" => [nil, nil, nil] }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles mixed nulls and values" do
        data = { "mixed" => [1, nil, "two", nil, true] }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "special string values" do
    context "reserved words" do
      it "quotes 'null' string" do
        data = { "value" => "null" }
        encoded = Cton.dump(data)
        expect(encoded).to include('"null"')
        expect(Cton.load(encoded)).to eq(data)
      end

      it "quotes 'true' and 'false' strings" do
        data = { "a" => "true", "b" => "false" }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "handles empty string" do
        data = { "empty" => "" }
        encoded = Cton.dump(data)
        expect(encoded).to include('""')
        expect(Cton.load(encoded)).to eq(data)
      end
    end
  end

  describe "validator error detection" do
    context "specific error types" do
      it "detects missing array length" do
        result = Cton.validate("arr[]=1,2")
        expect(result.valid?).to be false
      end

      it "detects unclosed arrays" do
        result = Cton.validate("arr[3=1,2,3")
        expect(result.valid?).to be false
      end

      it "detects invalid escape sequences" do
        result = Cton.validate('text="hello\\x"')
        expect(result.valid?).to be false
        expect(result.errors.first.message).to include("escape")
      end

      it "validates nested objects" do
        result = Cton.validate("user(name=Alice,profile(age=30))")
        expect(result.valid?).to be true
      end

      it "validates empty input" do
        result = Cton.validate("")
        expect(result.valid?).to be true
      end
    end
  end

  describe "stats advanced scenarios" do
    context "various data shapes" do
      it "calculates savings for deeply nested data" do
        data = { "a" => { "b" => { "c" => { "d" => [1, 2, 3] } } } }
        stats = Cton.stats(data)
        expect(stats.savings_percent).to be > 0
      end

      it "handles empty data" do
        data = {}
        stats = Cton.stats(data)
        expect(stats.json_chars).to eq(2) # "{}"
        expect(stats.cton_chars).to eq(0) # empty
      end

      it "handles array-only data" do
        data = { "items" => (1..10).to_a }
        stats = Cton.stats(data)
        expect(stats.estimated_cton_tokens).to be < stats.estimated_json_tokens
      end

      it "provides byte sizes for unicode" do
        data = { "emoji" => "🚀🌍✨" }
        stats = Cton.stats(data)
        expect(stats.json_bytes).to be > stats.json_chars
        expect(stats.cton_bytes).to be > stats.cton_chars
      end
    end
  end

  describe "type registry advanced" do
    context "inheritance support" do
      let(:base_class) do
        Class.new do
          attr_reader :value

          def initialize(value)
            @value = value
          end
        end
      end

      let(:derived_class) { Class.new(base_class) }

      after { Cton.clear_type_registry! }

      it "handles inherited types" do
        Cton.register_type(base_class) { |obj| { value: obj.value } }

        derived = derived_class.new(42)
        encoded = Cton.dump({ "item" => derived })
        expect(encoded).to include("value=42")
      end
    end

    context "error handling" do
      it "raises without block" do
        expect { Cton.register_type(String) }.to raise_error(ArgumentError)
      end

      it "raises for invalid mode" do
        expect { Cton.register_type(String, as: :invalid) { |s| s } }.to raise_error(ArgumentError)
      end
    end
  end

  describe "CLI integration" do
    context "command validation" do
      it "accepts minify option in dump" do
        data = { "a" => 1, "b" => 2 }
        inline = Cton.dump(data, separator: "")
        normal = Cton.dump(data)
        expect(inline.length).to be < normal.length
      end
    end
  end

  describe "round-trip stress tests" do
    context "complex payloads" do
      it "round-trips a realistic API response" do
        data = {
          "status" => "success",
          "data" => {
            "users" => [
              { "id" => 1, "name" => "Alice", "email" => "alice@test.com", "active" => true },
              { "id" => 2, "name" => "Bob", "email" => "bob@test.com", "active" => false }
            ],
            "pagination" => { "page" => 1, "per_page" => 20, "total" => 100 }
          },
          "meta" => { "version" => "1.0", "timestamp" => "2025-01-01T00:00:00Z" }
        }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "round-trips mixed array types" do
        data = {
          "items" => [
            "string",
            123,
            true,
            nil,
            { "nested" => "object" },
            [1, 2, 3]
          ]
        }
        encoded = Cton.dump(data)
        expect(Cton.load(encoded)).to eq(data)
      end

      it "round-trips with pretty formatting" do
        data = { "user" => { "name" => "Test", "settings" => { "theme" => "dark" } } }
        pretty = Cton.dump(data, pretty: true)
        expect(Cton.load(pretty)).to eq(data)
      end
    end
  end

  describe "performance characteristics" do
    context "table optimization" do
      it "uses table format for uniform hashes" do
        data = { "rows" => (1..5).map { |i| { "id" => i, "val" => i * 10 } } }
        encoded = Cton.dump(data)
        expect(encoded).to include("{id,val}")
        expect(encoded).not_to include("id=")
      end

      it "falls back to objects for non-uniform hashes" do
        data = { "rows" => [{ "a" => 1 }, { "b" => 2 }] }
        encoded = Cton.dump(data)
        expect(encoded).not_to include("{")
        expect(encoded).to include("a=1")
      end
    end
  end

  describe "validation result details" do
    context "error information" do
      it "provides ValidationError to_h" do
        result = Cton.validate("broken=(")
        error = result.errors.first
        hash = error.to_h
        expect(hash).to include(:message, :line, :column)
      end

      it "ValidationResult to_s for valid input" do
        result = Cton.validate("valid=true")
        expect(result.to_s).to eq("Valid CTON")
      end

      it "ValidationResult to_s lists errors" do
        result = Cton.validate('broken="unclosed')
        expect(result.to_s).to include("Invalid CTON")
      end
    end
  end
end
