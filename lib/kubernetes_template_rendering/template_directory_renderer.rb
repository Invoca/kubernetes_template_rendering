# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext' # for deep_merge
require 'invoca/utils'
require 'yaml'
require_relative 'resource_set'
require 'set'

# This class points to a collection of template directories to render, and a rendered_directory to render into.
# Optionally, some of the template directories may be omitted by including them in `omitted_names`.
module KubernetesTemplateRendering
  class TemplateDirectoryRenderer
    DEFINITIONS_FILENAME = "definitions.yaml"

    attr_reader :directories, :omitted_names, :rendered_directory, :cluster_type, :region, :color, :variable_overrides, :source_repo

    def initialize(directories:, rendered_directory:, omitted_names: [], cluster_type: nil, region: nil, color: nil, variable_overrides: nil, source_repo: nil)
      @directories        = directories_with_definitions(Array(directories))
      @omitted_names      = Array(omitted_names)
      @rendered_directory = rendered_directory
      @cluster_type       = cluster_type
      @region             = region
      @color              = color
      @variable_overrides = variable_overrides || {}
      @source_repo        = source_repo
    end

    def render(args)
      child_pids = []

      resource_sets.each do |name, resource_sets|
        puts "Rendering templates for definition #{Color.red(name)}..."
        resource_sets.each do |resource_set|
          if args.fork?
            if (pid = Process.fork)
              # this is the parent
              child_pids << pid
              wait_if_max_forked(child_pids)
            else
              # this is the child
              render_set(args, resource_set)
              Kernel.exit!(3) # skip at_exit handlers since parent will run those
            end
          else
            render_set(args, resource_set)
          end
        end
      end

      if args.fork?
        process_statuses = Process.waitall

        if (failed_processes = process_statuses.select { |_, status| !status.success? }).any?
          raise "Child process completed with non-zero status: #{failed_processes.inspect}"
        end
      end
    end

    private

    def read_definitions(path)
      File.read(path)
    end

    MAX_FORKED_PROCESSES = 9

    def wait_if_max_forked(child_pids)
      while child_pids.size >= MAX_FORKED_PROCESSES
        begin
          Process.waitpid # this is a race condition because 1 or more processes could exit before we get here
        rescue SystemCallError # this will happen if they all exited before we called waitpid
        end
        child_pids.delete_if do |pid|
          Process.waitpid(pid, Process::WNOHANG)
        rescue Errno::ECHILD # No child processes
          true
        end
      end
    end

    def render_set(args, resource_set)
      resource_set.render(args)
    rescue => ex
      raise "error rendering ResourceSet from #{resource_set.definitions_path}\n#{ex.class}: #{ex.message}"
    end

    def directories_with_definitions(directories)
      directories.select do |dir|
        definitions_path = definitions_path_for_dir(dir)
        File.exist?(definitions_path)
      end
    end

    def definitions_path_for_dir(dir)
      File.join(dir, DEFINITIONS_FILENAME)
    end

    def resource_sets
      @resource_sets ||= @directories.each_with_object({}) do |dir, hash|
        definitions_path = definitions_path_for_dir(dir)
        config = load_config(definitions_path)

        config.map do |name, config|
          next if omitted_names.include?(name)

          kubernetes_cluster_type = name.sub('SPP-PLACEHOLDER', 'staging').sub(/\..*/, '') # prod.gcp => prod

          hash[name] ||= []
          hash[name] << ResourceSet.new(
            config: config,
            template_directory: dir,
            rendered_directory: @rendered_directory,
            kubernetes_cluster_type: kubernetes_cluster_type,
            definitions_path: definitions_path,
            variable_overrides: @variable_overrides,
            source_repo: @source_repo
          )
        end
      end
    end

    def build_libsonnet(dir, config)
      fname = File.join(dir, 'definitions.libsonnet')
      existing = File.exists?(fname) ? File.read(fname) : ""
      proposed = build_json(config)

      if existing != proposed
        puts("Generating updated #{Color.magenta(File.basename(fname))}")
        File.write(fname, proposed)
      end
    end

    def build_json(config)
      hash = transform_for_jsonnet(config)
      JSON.pretty_generate(hash)
    end

    # This method ensures that OpenStructs are
    # converted to hashes to support to_json operation
    # It also converts any embedded variable place holders
    # into a Jsonnet friendly format:
    #
    # %{variable} is converted to %(variable)s which can
    # then be used with the Jsonnet function std.format
    def transform_for_jsonnet(hash)
      hash.transform_values do |value|
        case value
        when OpenStruct
          transform_for_jsonnet(value.to_h)
        when Hash
          transform_for_jsonnet(value)
        else
          value
        end
      end
    end

    def load_config(definitions_path)
      begin
        config = YAML.safe_load(read_definitions(definitions_path), aliases: true)
      rescue => ex
        raise "error loading YAML from #{definitions_path}:\n#{ex.class}: #{ex.message}"
      end

      expand_config(config).each_with_object({}) do |(name, data), hash|
        if !cluster_type || cluster_type == name.sub('SPP-PLACEHOLDER', 'staging').sub(/\..*/, '') # prod.gcp => prod
          cluster_type_config = OpenStruct.new(data)

          cluster_type_config.regions   = cluster_type_config.regions & [region] if region
          cluster_type_config.colors    = cluster_type_config.colors & [color]   if color

          hash[name] = cluster_type_config if (region.nil? && color.nil?) || (cluster_type_config.regions.any? && cluster_type_config.colors.any?)
        end
      end
    end

    # returns a copy of the given config hash with the COMMON: k-v removed and deep merged into the other config values
    # (explicit config values take precedence over COMMON: ones)
    def expand_config(config)
      common = config.delete('COMMON') || {}

      Hash[config.map { |k, v| [k, common.deep_merge(v)] }]
    end
  end
end
