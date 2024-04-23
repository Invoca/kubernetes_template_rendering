# frozen_string_literal: true

require "jsonnet"
require_relative "template"

module Invoca
  module KubernetesTemplates
    class JsonnetTemplate < Template
      MULTI_FILE_RENDER_KEY = "MULTI_FILE_RENDER"
      MULTI_FILE_RENDER_FILE_NAME_KEY = "MULTI_FILE_RENDER_NAME"

      class MultiFileJsonnetRenderError < StandardError; end

      def render(erb_binding: nil, jsonnet_library_path: nil)
        json_doc = render_json_doc_from_template(jsonnet_library_path)
        if multi_file_jsonnet_doc?(json_doc)
          render_multi_file_jsonnet!(json_doc)
        else
          with_auto_generated_yaml_comment(json_doc.to_yaml)
        end
      end

      private

      def render_json_doc_from_template(jsonnet_library_path)
        vm = Jsonnet::VM.new
        vm.tla_code("vars", variables.to_json)
        if jsonnet_library_path.nil?
          vm.jpath_add(File.expand_path('../../../../../vendor-jb', __dir__))
        else
          vm.jpath_add(jsonnet_library_path)
        end
        JSON.parse(vm.evaluate_file(template_path))
      end

      def multi_file_jsonnet_doc?(json_doc)
        json_doc[MULTI_FILE_RENDER_KEY]
      end

      # Multi-File JSONNET Template Structuring:
      # Top Level - Multi File Hash
      # Keys map to Either Hash or Array
      # If Array, the values of the array must be Hashs.
      # Hash can be either a normal Hash or another Multi-File Hash

      def render_multi_file_jsonnet!(json_doc, file_name_to_yaml_hash = {})
        json_doc.delete(MULTI_FILE_RENDER_KEY)
        json_doc.each do |key, value|
          case value
          when Hash
            render_json_doc(value, key, file_name_to_yaml_hash)
          when NilClass
            next
          else
            raise ArgumentError, "must be a Hash or NilClass, was #{value.inspect}"
          end
        end
        file_name_to_yaml_hash
      end

      def render_json_doc(json_doc, default_file_name, file_name_to_yaml_hash)
        if multi_file_jsonnet_doc?(json_doc)
          render_multi_file_jsonnet!(json_doc, file_name_to_yaml_hash)
        else
          file_name = file_name_from_object(json_doc, default: default_file_name)
          file_name_to_yaml_hash["#{file_name}.yaml"] = with_auto_generated_yaml_comment(json_doc.to_yaml)
        end
      end

      def validate_json_doc!(json_doc, context)
        json_doc.is_a?(Hash) or raise MultiFileJsonnetRenderError, context
      end

      def file_name_from_object(object, default: nil)
        if (base_name = object.delete(MULTI_FILE_RENDER_FILE_NAME_KEY))
          base_name
        else
          default
        end
      end
    end
  end
end
