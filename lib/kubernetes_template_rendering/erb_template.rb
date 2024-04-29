# frozen_string_literal: true

require_relative "template"

module KubernetesTemplateRendering
  class ErbTemplate < Template
    module Snippet
      def snippet(file)
        snippet = "#{File.dirname(@template_path)}/#{file}"
        content = File.read(snippet)
        erb = ERB.new(content, trim_mode: "-")
        erb.filename = snippet
        erb.result(variables_object._binding)
      end
    end

    include Snippet

    class VariablesClass < BasicObject
      include Snippet

      def initialize(template_path, variables)
        @template_path = template_path
        @variables = variables
      end

      def _binding
        ::Kernel.binding
      end

      def keys
        @variables.keys
      end

      def method_missing(sym, *args, &block)
        @variables.fetch(sym.to_s) # will raise KeyError if not in @variables hash
      end

      private

      def variables_object
        self
      end
    end

    def render(erb_binding: nil, jsonnet_library_path: nil)
      rendered_erb = render_erb(erb_binding)
      if template_path.end_with?("yaml.erb")
        with_auto_generated_yaml_comment(sort_yaml(rendered_erb))
      else
        rendered_erb
      end
    end

    private

    def variables_object
      VariablesClass.new(template_path, variables)
    end

    def render_erb(erb_binding)
      content = File.read(template_path)
      erb = ERB.new(content, trim_mode: "-")
      erb.filename = template_path
      erb_binding.nil? ? erb.result(variables_object._binding) : erb.result(erb_binding) # here is where we eval the template
    end

    def sort_yaml(erb_yaml)
      if (yaml_docs = YAML.load_stream(erb_yaml)).any?
        yaml_docs.map { |yaml_doc| sort_keys(yaml_doc).to_yaml }.join("\n")
      else
        erb_yaml
      end
    end

    def sort_keys(json_doc)
      case json_doc
      when Array
        json_doc.map { |v| sort_keys(v) }
      when Hash
        with_sorted_values = json_doc.transform_values { |v| sort_keys(v) }
        with_sorted_values.sort.to_h
      else
        json_doc
      end
    end
  end
end
