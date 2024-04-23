# frozen_string_literal: true

require "pathname"
require_relative "color"
require_relative "erb_template"
require_relative "jsonnet_template"

module Invoca
  module KubernetesTemplates
    class Resource
      class UnexpectedFileTypeError < StandardError; end

      attr_reader :variables, :template_path, :output_directory

      def initialize(template_path:, definitions_path:, variables:, output_directory:, output_filename: nil)
        @template_path    = template_path
        @definitions_path = definitions_path
        @variables        = variables
        @output_directory = output_directory
        @output_filename  = output_filename || template_filename(template_path)
      end

      def render(args)
        write_template(args)
      end

      private

      def rendered_template(args)
        @rendered_template ||= template_klass.render(@template_path, variables, jsonnet_library_path: args.jsonnet_library_path)
      end

      def write_template(args)
        print_status

        # If a Hash is returned, that means this is a multi-file template, meaning we need to iterate over the hash.
        # Else a String is returned and we can write it directly to the output file.
        rt = rendered_template(args)

        if args.render_files?
          if rt.is_a?(Hash)
            rt.each do |filename, contents|
              File.write(output_path(filename), contents)
            end
          else
            File.write(output_path(@output_filename), rt)
          end
        end
      end

      def template_klass
        case @template_path
        when /\.erb\z/
          ErbTemplate
        when /\.jsonnet\z/
          JsonnetTemplate
        else
          raise UnexpectedFileTypeError, "Unexpected file type #{@template_path}"
        end
      end

      def print_status
        variable_output = variables.map { |k, v| "#{Color.magenta(k)}=#{Color.blue(v)}" }.join(', ')
        puts "Writing #{Color.magenta(File.basename(output_path(@output_filename)))} with variables #{variable_output}\n\n"
      end

      def output_path(filename)
        File.join(@output_directory, filename)
      end

      def template_filename(template_path)
        if template_path.match(/\.erb\z/)
          File.basename(template_path, '.erb')

        elsif template_path.match(/\.jsonnet\z/)
          Pathname.new(template_path).basename.sub_ext('.yaml')

        else
          raise "Unexpected template_path format: #{template_path}"
        end
      end
    end
  end
end
