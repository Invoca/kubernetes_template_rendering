# frozen_string_literal: true

require_relative "resource"
require_relative "deploy_grouped_resource"

# This class points to the resources in a given template_directory for a given kubernetes_cluster_type like 'ops' or 'prod' or 'ci'.
# `config` contains the definitions found in `definitions_path`.
#   The most important config is "directory" which is a pattern like "%{region}/%{type}/%{color}/staging-ops".
#   The config "regions", "colors" are the sets of regions and colors to render for.
# It renders into `rendered_directory`.
module KubernetesTemplateRendering
  class ResourceSet
    attr_reader :variables, :output_directory, :deploy_group_config, :omitted_resources,
                :template_directory, :target_output_directory, :regions, :colors,
                :definitions_path, :kubernetes_cluster_type, :variable_overrides,
                :source_repo

    def initialize(config:, template_directory:, rendered_directory:, definitions_path:, kubernetes_cluster_type:, variable_overrides: {}, source_repo: nil)
      @variables               = config["variables"] || {}
      @deploy_group_config     = config["deploy_groups"]
      @omitted_resources       = config["omitted_resources"]
      @template_directory      = template_directory
      @target_output_directory = config["directory"] or raise ArgumentError, "missing 'directory:' in #{config.inspect}"
      @regions                 = config["regions"] || []
      @colors                  = config["colors"] || []
      @rendered_directory      = rendered_directory
      @definitions_path        = definitions_path
      @kubernetes_cluster_type = kubernetes_cluster_type
      @variable_overrides      = variable_overrides
      @source_repo             = source_repo
      @resources               = {}

      if @kubernetes_cluster_type != "kube-platform"
        @target_output_directory.include?("%{plain_region}") or raise "#{@template_directory}: target_output_directory #{@target_output_directory} needs %{plain_region}"
      end
    end

    def normal_render(args)
      dynamic_output_directory? and raise "Directory must not be dynamic: #{target_output_directory}"

      variables["kubernetes_cluster_type"] = @kubernetes_cluster_type

      if (plain_region = variables["plain_region"])
        default_region_vars(plain_region)
      end

      output_directory = File.join(@rendered_directory, target_output_directory)
      render_create_directory(args, output_directory)
    end

    def render(args)
      @regions.any? or raise "#{template_directory}: must have at least one region"
      @colors.any? or raise "#{template_directory}: must have at least one color"

      variables["kubernetes_cluster_type"] = @kubernetes_cluster_type

      @regions.each do |plain_region|
        default_region_vars(plain_region)

        @colors.each do |c|
          variables["color"] = c
          output_directory = File.join(@rendered_directory, format(@target_output_directory, plain_region: plain_region, color: c, type: @kubernetes_cluster_type))
          render_create_directory(args, output_directory)
        end
      end
    end

    def render_create_directory(args, output_directory)
      prune_directory(output_directory) if args.prune?
      create_directory(output_directory)
      puts "Rendering templates to: #{Color.magenta(output_directory)}"
      puts "Variable assignments:"
      variables.each { |k, v| puts "\t#{Color.magenta(k)}=#{Color.blue(v)}" }
      puts
      if omitted_resources
        puts "Omitted resources:"
        omitted_resources.each { |ot| puts "\t#{ot}" }
      end
      puts
      resources(output_directory).each do |resource|
        resource.render(args)
      end
      puts
    end

    private

    CLOUD_REGION_TO_PROVIDER_AND_DATACENTER = {
      # Note: The names below should match RegionDiscovery from process_settings-production.
      # https://github.com/Invoca/process_settings-production/blob/main/settings/region_discovery/production_regions.yml
      "us-east-1"    => ['aws', "AWS-us-east-1"],
      "us-east-2"    => ['aws', "AWS-us-east-2"],
      "us-central1"  => ['gcp', "GCE-us-central1"],
      "us-west2"     => ['gcp', "GCE-us-west2"],
      "eu-central-1" => ['aws', "AWS-eu-central-1"],
      "eu-west-1"    => ['aws', "AWS-eu-west-1"],
      "europe-west4" => ['gcp', "GCE-europe-west4"],

      # other regions
      "us-east1"    => ['gcp', "GCE-us-east1"],
      "us-west1"    => ['gcp', "GCE-us-west1"],
      "local"       => ['',    "local"]
    }.freeze

    # The zone to use for failure-domain.beta.kubernetes.io/zone or topology.kubernetes.io/zone by DeployGroup
    AVAILABILITY_ZONE_FOR_DEPLOY_GROUP = {
      "us-east-1" => {
        "primary" => "us-east-1c",
        "secondary" => "us-east-1d",
        "tertiary" => "us-east-1b"
      },
      "us-east-2" => {
        "primary" => "us-east-2a",
        "secondary" => "us-east-2b",
        "tertiary" => "us-east-2c"
      },
      "us-central1" => {
        "primary" => "us-central1-a",
        "secondary" => "us-central1-b",
        "tertiary" => "us-central1-c"
      },
      "us-west2" => {
        "primary" => "us-west2-a",
        "secondary" => "us-west2-b",
        "tertiary" => "us-west2-c"
      },
      "eu-central-1" => {
        "primary" => "eu-central-1a",
        "secondary" => "eu-central-1b",
        "tertiary" => "eu-central-1c"
      },
      "eu-west-1" => {
        "primary" => "eu-west-1a",
        "secondary" => "eu-west-1b",
        "tertiary" => "eu-west-1c"
      },
      "europe-west4" => {
        "primary" => "europe-west4-a",
        "secondary" => "europe-west4-b",
        "tertiary" => "europe-west4-c"
      },
      "local" => {},
      "us-west1" => {},
      "us-east1" => {}
    }

    def default_region_vars(plain_region)
      variables.has_key?("region") and raise "replace region with plain_region"
      variables["plain_region"] = plain_region
      cloud_datacenter_and_provider = CLOUD_REGION_TO_PROVIDER_AND_DATACENTER[plain_region] or raise "no CLOUD_REGION_TO_PROVIDER_AND_DATACENTER entry found for #{plain_region.inspect}"
      variables["cloud_provider"], variables["cloud_datacenter"] = cloud_datacenter_and_provider
      variables["cloud_region"] = variables["cloud_datacenter"] # for compatibility with old resource files; cloud_datacenter is preferred now
      if plain_region == "local"
        variables["data_silo"] ||= "local"
      elsif plain_region.start_with?("us-")
        variables["data_silo"] ||= "us"
      end

      # cannot do ||= because we want to reset when plain_region changes
      variables["availability_zone_for_deploy_group"] = AVAILABILITY_ZONE_FOR_DEPLOY_GROUP[plain_region] or raise "no AVAILABILITY_ZONE_FOR_DEPLOY_GROUP mapping found for #{plain_region.inspect}"
    end

    def create_directory(directory)
      unless File.exist?(directory)
        puts <<~MESSAGE

          Directory #{Color.magenta(directory)} doesn't exist, #{Color.green('creating it')}

        MESSAGE
        FileUtils.mkdir_p(directory)
      end
    end

    def prune_directory(directory)
      if File.exist?(directory)
        puts <<~MESSAGE

          The `prune` flag is set to true, #{Color.green('pruning')} directory #{Color.magenta(directory)} before rendering

        MESSAGE
        FileUtils.rm_rf(directory)
      end
    end

    def resources(output_directory)
      @resources[output_directory] ||= standard_resources(output_directory) + grouped_resources(output_directory)
    end

    def standard_resources(output_directory)
      standard_template_paths.map do |path|
        Resource.new(template_path: path, definitions_path:, variables:, output_directory:, variable_overrides:, source_repo:)
      end
    end

    def grouped_resources(output_directory)
      deploy_grouped_template_paths.map do |path|
        DeployGroupedResource.new(
          template_path: path,
          definitions_path: @definitions_path,
          variables: variables,
          output_directory: output_directory,
          groups_to_render: deploy_groups_to_render,
          template_path_exclusions: deploy_group_config["exclude_files"],
          group_variable_name: deploy_group_config["variable_name"]
        )
      end
    end

    def standard_template_paths
      @standard_template_paths ||=
        (Dir[File.join(template_directory, "*.yaml.erb")] +
          Dir[File.join(template_directory, '*.jsonnet')]) -
        deploy_grouped_template_paths - omitted_resource_paths
    end

    def deploy_grouped_template_paths
      @deploy_grouped_template_paths ||=
        if deploy_group_config
          deploy_group_config["files"]&.map { |file| File.join(template_directory, file) } ||
            (Dir[File.join(template_directory, "*-deploy.yaml.erb")] + Dir[File.join(template_directory, "*-deploy.jsonnet")]) - omitted_resource_paths
        else
          []
        end
    end

    def omitted_resource_paths
      @omitted_resource_paths ||= omitted_resources&.map { |file| File.join(template_directory, file) } || []
    end

    def deploy_groups_to_render
      group_names = deploy_group_config["group_names"]
      if array_of_arrays?(group_names)
        first, *rest = group_names
        first.product(*rest).map { |group| group.join("-") }
      else
        group_names
      end
    end

    def array_of_arrays?(array)
      array.all? { |item| item.is_a?(Array) }
    end
  end
end
