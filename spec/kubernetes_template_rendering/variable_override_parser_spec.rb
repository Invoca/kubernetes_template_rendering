# frozen_string_literal: true

require_relative "../../lib/kubernetes_template_rendering/variable_override_parser"

RSpec.describe KubernetesTemplateRendering::VariableOverrideParser do
  describe ".merge_override!" do
    let(:overrides) { {} }

    def merge(raw)
      described_class.merge_override!(overrides, raw)
    end

    context "with a legacy KEY:VALUE (no '.' in key)" do
      it "sets a top-level key with the raw string value" do
        merge("deploySha:abc123")
        expect(overrides).to eq("deploySha" => "abc123")
      end

      it "keeps numeric-looking values as strings" do
        merge("deploySha:12345")
        expect(overrides).to eq("deploySha" => "12345")
      end

      it "keeps boolean-looking values as strings" do
        merge("enabled:true")
        expect(overrides).to eq("enabled" => "true")
      end

      it "splits on the first colon only" do
        merge("image:registry:5000/app")
        expect(overrides).to eq("image" => "registry:5000/app")
      end

      it "silently ignores an argument with no colon" do
        merge("deploySha")
        expect(overrides).to eq({})
      end
    end

    context "with a dotted-path KEY" do
      it "builds a nested hash with a JSON-coerced integer" do
        merge("components.webServer.hpa.minReplicas:2")
        expect(overrides).to eq("components" => { "webServer" => { "hpa" => { "minReplicas" => 2 } } })
      end

      it "JSON-coerces floats, booleans, and null" do
        merge("a.float:2.5")
        merge("a.bool:false")
        merge("a.nil:null")
        expect(overrides).to eq("a" => { "float" => 2.5, "bool" => false, "nil" => nil })
      end

      it "keeps a JSON-quoted value as a string" do
        merge(%q{a.b:"2"})
        expect(overrides).to eq("a" => { "b" => "2" })
      end

      it "falls back to the raw string for non-JSON values" do
        merge("a.b:hello")
        merge("a.c:02")
        expect(overrides).to eq("a" => { "b" => "hello", "c" => "02" })
      end

      it "treats backslash-escaped dots as literal dots in a segment" do
        merge('metadata.labels.app\.kubernetes\.io/name:foo')
        expect(overrides).to eq("metadata" => { "labels" => { "app.kubernetes.io/name" => "foo" } })
      end

      it "supports an escaped-dot-only key as a typed top-level override" do
        merge('replica\.count:3')
        expect(overrides).to eq("replica.count" => 3)
      end

      it "deep-merges sibling paths" do
        merge("components.webServer.hpa.minReplicas:2")
        merge("components.webServer.hpa.maxReplicas:4")
        expect(overrides).to eq("components" => { "webServer" => { "hpa" => { "minReplicas" => 2, "maxReplicas" => 4 } } })
      end

      it "lets the later value win for the same path" do
        merge("a.b:1")
        merge("a.b:2")
        expect(overrides).to eq("a" => { "b" => 2 })
      end

      it "replaces a hash wholesale when a scalar is merged over it" do
        merge("a.b.c:1")
        merge("a.b:scalar")
        expect(overrides).to eq("a" => { "b" => "scalar" })
      end

      ["a..b:1", ".a:1", "a.:1"].each do |raw|
        it "raises ParseError for the empty path segment in #{raw.inspect}" do
          expect { merge(raw) }.to raise_error(described_class::ParseError, /empty path segment/)
        end
      end
    end
  end

  describe ".merge_json!" do
    let(:overrides) { {} }

    it "deep-merges a JSON object" do
      described_class.merge_json!(overrides, '{"components":{"webServer":{"hpa":{"minReplicas":3}}}}')
      expect(overrides).to eq("components" => { "webServer" => { "hpa" => { "minReplicas" => 3 } } })
    end

    it "raises ParseError for invalid JSON" do
      expect { described_class.merge_json!(overrides, "{nope") }
        .to raise_error(described_class::ParseError, /not valid JSON/)
    end

    it "raises ParseError for a non-object JSON value" do
      expect { described_class.merge_json!(overrides, "[1,2]") }
        .to raise_error(described_class::ParseError, /must be a JSON object/)
    end
  end
end
