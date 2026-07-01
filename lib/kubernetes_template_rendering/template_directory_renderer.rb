# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext' # for deep_merge
require 'invoca/utils'
require 'pathname'
require 'yaml'
require_relative 'resource_set'
require_relative 'reconciler'
require 'set'

# This class points to a collection of template directories to render, and a rendered_directory to render into.
# Optionally, some of the template directories may be omitted by including them in `omitted_names`.
module KubernetesTemplateRendering
  class TemplateDirectoryRenderer
    DEFINITIONS_FILENAME = "definitions.yaml"
    SPP_FENCE_DIRNAME = "spp"

    attr_reader :directories, :omitted_names, :rendered_directory, :cluster_type, :region, :color, :variable_overrides, :source_repo, :spps

    def initialize(directories:, rendered_directory:, omitted_names: [], cluster_type: nil, region: nil, color: nil, variable_overrides: nil, source_repo: nil, spps: [])
      @directories        = directories_with_definitions(Array(directories))
      @omitted_names      = Array(omitted_names)
      @rendered_directory = rendered_directory
      @cluster_type       = cluster_type
      @region             = region
      @color              = color
      @variable_overrides = variable_overrides || {}
      @source_repo        = source_repo
      @spps               = Array(spps)
    end

    def render(args)
      if args.reconcile?
        sweep_scopes = collect_reconcile_scopes # validates out-of-prefix before any writes
        reconciler   = Reconciler.new(@rendered_directory) # marker captured before rendering/forking
      end

      child_pids = []
      failed_processes = [] # [[pid, status]]

      resource_sets.each do |name, resource_sets|
        puts "Rendering templates for definition #{Color.red(name)}..."
        resource_sets.each do |resource_set|
          if args.fork?
            if (pid = Process.fork)
              # this is the parent
              child_pids << pid
              wait_if_max_forked(child_pids, failed_processes)
            else
              # this is the child
              render_set(args, resource_set)
              Kernel.exit!(0) # skip at_exit handlers since parent will run those
            end
          else
            render_set(args, resource_set)
          end
        end
      end

      if args.fork?
        Process.waitall.each do |pid, status|
          status.success? or failed_processes << [pid, status]
        end

        if failed_processes.any?
          raise "Child process completed with non-zero status: #{failed_processes.inspect}"
        end
      end

      reconcile_sweep(reconciler, sweep_scopes) if args.reconcile?
    end

    private

    # Collects sweep roots across all rendered resource sets and validates that each stays within
    # rendered_directory (out-of-prefix, full or relative `..`, is a hard error).
    #
    # Returns two categories:
    #   base_roots — non-SPP entries' shared parent (e.g. <region>/<cluster_type>/<color>/);
    #                swept with an spp/ fence so sibling SPP directories are never touched.
    #   spp_roots  — the specific SPP directory/directories that were rendered (e.g. spp/<spp-name>/);
    #                swept without a fence since we are already inside exactly one SPP directory.
    #                With --spp the SPP-PLACEHOLDER root expands to one root per requested SPP target;
    #                without it, only the SPP-PLACEHOLDER root itself is swept (deleted-SPP cleanup
    #                stays a manual git rm per the teardown runbook).
    def collect_reconcile_scopes
      scopes = resource_sets.values.flatten.flat_map(&:reconcile_scopes)
      scopes.each { |scope| Reconciler.validate_within_scope!(scope[:base_root], @rendered_directory) }

      base_roots = []
      spp_roots  = []
      scopes.each do |scope|
        if within_spp_subtree?(scope[:base_root])
          spp_roots.concat(spp_reconcile_roots(scope))
        else
          base_roots << scope[:base_root]
        end
      end
      spp_roots.each { |r| Reconciler.validate_within_scope!(r, @rendered_directory) }
      { base_roots: base_roots.uniq, spp_roots: spp_roots.uniq }
    end

    # Expands an SPP sweep root into the concrete roots to sweep for this run.
    # Without --spp, the placeholder root (spp/SPP-PLACEHOLDER) is swept as-is. With --spp, each
    # requested target replaces the SPP-PLACEHOLDER segment (spp/staging-qa02a, ...), so only the
    # requested SPP subtrees are swept and SPP-PLACEHOLDER / unrequested SPP siblings are left intact.
    def spp_reconcile_roots(scope)
      root = spp_sweep_root(scope)
      return [root] if @spps.empty?
      return [root] unless root.include?(ResourceSet::SPP_PLACEHOLDER)

      @spps.map { |spp_name| root.sub(ResourceSet::SPP_PLACEHOLDER, spp_name) }
    end

    def within_spp_subtree?(root)
      Pathname.new(root).relative_path_from(Pathname.new(@rendered_directory)).each_filename.include?(SPP_FENCE_DIRNAME)
    end

    # When the directory pattern has no service subdirectory (e.g. `.../spp/SPP-PLACEHOLDER`),
    # base_root lands at the `spp/` level itself — sweeping that would touch all SPP siblings.
    # Use output_directory (= `spp/<spp-name>`) in that case instead.
    def spp_sweep_root(scope)
      File.basename(scope[:base_root]) == SPP_FENCE_DIRNAME ? scope[:output_directory] : scope[:base_root]
    end

    def reconcile_sweep(reconciler, scopes)
      scopes[:base_roots].each { |r| reconciler.sweep!(root: r, fences: [File.join(r, SPP_FENCE_DIRNAME)]) }
      scopes[:spp_roots].each  { |r| reconciler.sweep!(root: r) }
    ensure
      reconciler.finish!
    end

    def read_definitions(path)
      File.read(path)
    end

    MAX_FORKED_PROCESSES = 9

    def wait_if_max_forked(child_pids, failed_processes)
      while child_pids.size >= MAX_FORKED_PROCESSES
        begin
          pid, exit_status = Process.waitpid2 # this is a race condition because 1 or more processes could exit before we get here
          exit_status.success? or failed_processes << [pid, exit_status]
        rescue SystemCallError # this will happen if they all exited before we called waitpid
        end
        child_pids.delete_if do |pid|
          begin
            _, exit_status = Process.waitpid2(pid, Process::WNOHANG)
            if exit_status && !exit_status.success?
              failed_processes << [pid, exit_status]
            end
          rescue Errno::ECHILD # No child processes
            true
          end
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

          kubernetes_cluster_type = name.sub(ResourceSet::SPP_PLACEHOLDER, 'staging').sub(/\..*/, '') # prod.gcp => prod
          spp = name.include?(ResourceSet::SPP_PLACEHOLDER)

          hash[name] ||= []
          hash[name] << ResourceSet.new(
            config: config,
            template_directory: dir,
            rendered_directory: @rendered_directory,
            kubernetes_cluster_type: kubernetes_cluster_type,
            spp: spp,
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
        if !cluster_type || cluster_type == name.sub(ResourceSet::SPP_PLACEHOLDER, 'staging').sub(/\..*/, '') # prod.gcp => prod
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
