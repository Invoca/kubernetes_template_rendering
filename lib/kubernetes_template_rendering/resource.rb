# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "color"
require_relative "erb_template"
require_relative "jsonnet_template"

module KubernetesTemplateRendering
  class Resource
    class UnexpectedFileTypeError < StandardError; end

    attr_reader :variables, :variable_overrides, :template_path, :output_directory, :source_repo

    def initialize(template_path:, definitions_path:, variables:, output_directory:, output_filename: nil, variable_overrides: {}, source_repo: nil)
      @template_path      = template_path
      @definitions_path   = definitions_path
      @variables          = variables
      @variable_overrides = variable_overrides
      @output_directory   = output_directory
      @source_repo        = source_repo
      @output_filename    = output_filename || template_filename(template_path)
    end

    def render(args)
      write_template(args)
    end

    private

    def rendered_template(args)
      @rendered_template ||= template_klass.render(@template_path, variables, variable_overrides:, source_repo:, jsonnet_library_path: args.jsonnet_library_path)
    end

    def write_template(args)
      print_status

      # If a Hash is returned, that means this is a multi-file template, meaning we need to iterate over the hash.
      # Else a String is returned and we can write it directly to the output file.
      rt = rendered_template(args)

      if args.render_files?
        if rt.is_a?(Hash)
          rt.each do |filename, contents|
            path = output_path(filename)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, contents)
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
      path = File.join(@output_directory, filename)
      base = File.expand_path(@output_directory)
      expanded = File.expand_path(path)

      unless expanded == base || expanded.start_with?(base + File::SEPARATOR)
        raise ArgumentError, "output filename #{filename.inspect} escapes output directory #{@output_directory}"
      end

      validate_resolved_containment!(File.dirname(expanded), base, filename)
      path
    end

    def validate_resolved_containment!(target_dir, base, filename)
      base_real = realpath_or_expand(base)
      current = base_real
      Pathname.new(target_dir).relative_path_from(Pathname.new(base)).each_filename do |part|
        candidate = File.join(current, part)
        if File.symlink?(candidate)
          raise ArgumentError, "output filename #{filename.inspect} escapes output directory #{@output_directory}"
        end

        if File.exist?(candidate)
          current = File.realpath(candidate)
        else
          break
        end
      end

      return if current == base_real || current.start_with?(base_real + File::SEPARATOR)

      raise ArgumentError, "output filename #{filename.inspect} escapes output directory #{@output_directory}"
    end

    def realpath_or_expand(path)
      File.realpath(path)
    rescue Errno::ENOENT
      File.expand_path(path)
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
