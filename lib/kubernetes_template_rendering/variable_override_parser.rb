# frozen_string_literal: true

require "json"
require "active_support"
require "active_support/core_ext/hash/deep_merge"

module KubernetesTemplateRendering
  # Parses --variable-override / --variable-override-json values into (possibly nested)
  # override fragments and deep-merges them, in command-line order, into one overrides hash.
  #
  # Key forms:
  #   * Legacy: KEY contains no "." -> top-level key, value kept as the raw string
  #     (exactly the pre-0.7.0 behavior; never type-coerced).
  #   * Dotted: KEY contains "." -> split on unescaped dots into a nested path ("\." is a
  #     literal dot within a segment). The value is JSON-coerced when it parses as JSON
  #     (2 -> Integer, true/false -> booleans, null -> nil, "2" -> String), else kept raw.
  class VariableOverrideParser
    class ParseError < StandardError; end

    UNESCAPED_DOT = /(?<!\\)\./.freeze

    class << self
      # Deep-merges a KEY:VALUE override fragment into +overrides+.
      #
      # @param overrides [Hash] accumulated overrides hash (mutated in place)
      # @param raw [String] raw KEY:VALUE argument
      # @return [Hash] +overrides+ after merging
      def merge_override!(overrides, raw)
        key, value = raw.split(":", 2)
        return overrides if key.nil? || value.nil? # preserve legacy silent-skip of colon-less args

        overrides.deep_merge!(fragment_for(key, value))
      end

      # Deep-merges a JSON object string into +overrides+.
      #
      # @param overrides [Hash] accumulated overrides hash (mutated in place)
      # @param json [String] JSON object string
      # @return [Hash] +overrides+ after merging
      # @raise [ParseError] when +json+ is invalid or not a JSON object
      def merge_json!(overrides, json)
        fragment =
          begin
            JSON.parse(json)
          rescue JSON::ParserError => ex
            raise ParseError, "--variable-override-json value is not valid JSON: #{ex.message}"
          end
        fragment.is_a?(Hash) or raise ParseError, "--variable-override-json value must be a JSON object, got #{fragment.class}: #{json.inspect}"
        overrides.deep_merge!(fragment)
      end

      private

      def fragment_for(key, value)
        if key.include?(".")
          nest(path_segments(key), coerce(value))
        else
          { key => value } # legacy: literal key, raw string value
        end
      end

      def path_segments(key)
        segments = key.split(UNESCAPED_DOT, -1)
        segments.none?(&:empty?) or
          raise ParseError, "--variable-override key #{key.inspect} has an empty path segment (leading, trailing, or doubled '.')"
        segments.map { |segment| segment.gsub("\\.", ".") }
      end

      def nest(segments, value)
        segments.reverse.reduce(value) { |acc, segment| { segment => acc } }
      end

      def coerce(value)
        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end
  end
end
