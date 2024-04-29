# frozen_string_literal: true

require_relative "../../lib/kubernetes_template_rendering/deploy_grouped_resource"

RSpec.describe KubernetesTemplateRendering::DeployGroupedResource do
  subject(:grouped) do
    described_class.new(
      template_path: template_path,
      definitions_path: definitions_path,
      variables: variables,
      output_directory: output_directory,
      groups_to_render: groups_to_render,
      template_path_exclusions: template_path_exclusions,
      group_variable_name: group_variable_name
    )
  end

  let(:rendered_directory) { "zz-rendered" }
  let(:template_directory) { "td" }
  let(:template_path) { "#{template_directory}/template-deploy.jsonnet" }
  let(:definitions_path) { "td/definitions.yaml" }
  let(:variables) { { "a" => "1", "b" => "2" } }
  let(:output_directory) { "dir" }
  let(:groups_to_render) { ["primary", "secondary"] }
  let(:template_path_exclusions) { }
  let(:group_variable_name) { }
  let(:args) { KubernetesTemplateRendering::CLI::Arguments.new(rendered_directory, template_directory, false, '') }

  before do
    stub_puts
  end

  context "when no templates are excluded" do
    it "creates and renders a Resource for each deploy group" do
      groups_to_render.each do |group|
        resource = instance_double(KubernetesTemplateRendering::Resource)

        expect(KubernetesTemplateRendering::Resource).to receive(:new)
                              .with(
                                template_path: template_path,
                                variables: variables.merge("deploy_group" => group),
                                output_directory: output_directory,
                                output_filename: "template-#{group}-deploy.yaml",
                                definitions_path: definitions_path
                              )
                              .and_return(resource)

        expect(resource).to receive(:render)
      end

      grouped.render(args)
    end
  end

  context "when templates are excluded" do
    let(:template_path_exclusions) do
      {
        "primary" => [File.basename(template_path)]
      }
    end

    it "excludes the template path from the deploy group" do
      resource = instance_double(KubernetesTemplateRendering::Resource)
      expect(KubernetesTemplateRendering::Resource).to receive(:new)
                            .with(
                              template_path: template_path,
                              variables: variables.merge("deploy_group" => "secondary"),
                              output_directory: output_directory,
                              output_filename: "template-secondary-deploy.yaml",
                              definitions_path: definitions_path
                            )
                            .and_return(resource)
      expect(resource).to receive(:render)
      grouped.render(args)
    end
  end

  context "when group_variable_name is provided" do
    let(:group_variable_name) { "owner" }

    it "provides the group under the provided group_variable_name" do
      groups_to_render.each do |group|
        resource = instance_double(KubernetesTemplateRendering::Resource)

        expect(KubernetesTemplateRendering::Resource).to receive(:new)
                              .with(
                                template_path: template_path,
                                variables: variables.merge("owner" => group),
                                output_directory: output_directory,
                                output_filename: "template-#{group}-deploy.yaml",
                                definitions_path: definitions_path
                              )
                              .and_return(resource)

        expect(resource).to receive(:render)
      end

      grouped.render(args)
    end
  end
end
