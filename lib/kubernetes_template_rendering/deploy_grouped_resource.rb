# frozen_string_literal: true

require_relative "resource"

module KubernetesTemplateRendering
  class DeployGroupedResource
    DEFAULT_GROUP_VARIABLE_NAME = "deploy_group"

    attr_reader :groups_to_render, :variables, :template_path, :output_directory, :template_path_exclusions, :group_variable_name

    def initialize(template_path:, definitions_path:, variables:, output_directory:, groups_to_render:, template_path_exclusions:, group_variable_name: nil)
      @template_path    = template_path
      @definitions_path = definitions_path
      @variables        = variables
      @output_directory = output_directory
      @groups_to_render = groups_to_render
      @template_path_exclusions = template_path_exclusions || {}
      @group_variable_name = group_variable_name || DEFAULT_GROUP_VARIABLE_NAME
    end

    def render(args)
      @resources =
        groups_to_render.map do |deploy_group|
          if template_is_excluded?(deploy_group)
            puts "Skipping #{Color.magenta(template_path_basename)} for #{deploy_group} deploy group due to it being " \
              "excluded within the deploy group config\n\n"
            nil
          else
            vars     = variables.merge(group_variable_name => deploy_group)
            filename = filename_for_deploy_group(deploy_group)
            Resource.new(template_path: template_path, definitions_path: @definitions_path, variables: vars, output_directory: output_directory, output_filename: filename).tap do |resource|
              resource.render(args) if args.render_files?
            end
          end
        end.compact
    end

    private

    def template_path_basename
      @template_path_basename ||= File.basename(template_path)
    end

    def template_is_excluded?(deploy_group)
      @template_path_exclusions[deploy_group]&.include?(template_path_basename)
    end

    def filename_for_deploy_group(group)
      case @template_path
      when /.erb/
        File.basename(template_path, ".erb").sub(/([^-.]+)\.yaml$/, "#{group}-\\1.yaml")
      when /.jsonnet/
        File.basename(template_path).sub(/([^-.]+)\.jsonnet$/, "#{group}-\\1.yaml")
      else
        raise "unexpected template_path #{template_path.inspect}"
      end
    end
  end
end
