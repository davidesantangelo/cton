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
        { "id" => 1, "name" => "Blue Lake Trail", "distanceKm" => 7.5, "elevationGain" => 320, "companion" => "ana", "wasSunny" => true },
        { "id" => 2, "name" => "Ridge Overlook", "distanceKm" => 9.2, "elevationGain" => 540, "companion" => "luis", "wasSunny" => false },
        { "id" => 3, "name" => "Wildflower Loop", "distanceKm" => 5.1, "elevationGain" => 180, "companion" => "sam", "wasSunny" => true }
      ]
    }
  end

  let(:sample_cton) do
    [
      'context(task="Our favorite hikes together",location=Boulder,season=spring_2025)',
      'friends[3]=ana,luis,sam',
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
        expect(Cton.dump(payload)).to eq('price=12.34')
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

    context "table detection" do
      it "compacts uniform scalar hashes" do
        payload = {
          "rows" => [
            { "a" => 1, "b" => 2 },
            { "a" => 3, "b" => 4 }
          ]
        }

        expect(Cton.dump(payload)).to eq('rows[2]{a,b}=1,2;3,4')
      end

      it "leaves heterogeneous arrays as nested objects" do
        payload = {
          "rows" => [
            { "a" => 1 },
            { "b" => 2 }
          ]
        }

        expect(Cton.dump(payload)).to eq('rows[2]=(a=1),(b=2)')
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
        cton = 'payload(meta=(count=2,flags=[2]=true,false),items=[2]=(id=1,details=(notes=[2]=alpha,beta)),(id=2,details=(notes=[0]=)))'
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
        inline = 'alpha(value=1) beta[2]=true,false gamma()'
        expect(Cton.load(inline)).to eq(
          "alpha" => { "value" => 1 },
          "beta" => [true, false],
          "gamma" => {}
        )
      end
    end

    context "error handling" do
      it "rejects arrays with fewer values than advertised" do
        expect { Cton.load('friends[2]=ana') }.to raise_error(Cton::ParseError)
      end

      it "rejects malformed tables" do
        expect { Cton.load('rows[1]{id,name}=42') }.to raise_error(Cton::ParseError)
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
        "meta" => { "count" => 2, "labels" => ["alpha", "beta"] },
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
end
