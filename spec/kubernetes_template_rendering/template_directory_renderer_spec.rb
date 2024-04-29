# frozen_string_literal: true

require 'tmpdir'

require_relative "../../lib/kubernetes_template_rendering/template_directory_renderer"
require_relative "../../lib/kubernetes_template_rendering/cli_arguments"

RSpec.describe KubernetesTemplateRendering::TemplateDirectoryRenderer do
  subject(:dir_renderer) { described_class.new(directories: [template_directory], rendered_directory: rendered_directory) }
  let(:rendered_directory) { Dir.mktmpdir }
  let(:template_directory) { Dir.mktmpdir }
  let(:args) { KubernetesTemplateRendering::CLIArguments.new(rendered_directory, template_directory, false, '') }
  let(:variables) { { "variable1" => "value1", "variable2" => "value2" } }

  before do
    stub_puts
  end

  after do
    FileUtils.rm_r(rendered_directory)
    FileUtils.rm_r(template_directory)
  end

  { "test": "test", "prod.gcp": "prod", "SPP-PLACEHOLDER": "staging", "SPP-PLACEHOLDER.eu": "staging" }.each do |resource_definition_name, expected_kubernetes_cluster_type|
    it "builds a ResourceSet with an appropriate kubernetes_cluster_type for each directory and calls render on it" do
      definition = build_definition(name: resource_definition_name.to_s, rendered_directory: rendered_directory, template_directory: template_directory, variables: variables)
      definitions_path = File.join(template_directory, described_class::DEFINITIONS_FILENAME)
      File.write(definitions_path, definition.to_yaml)

      expected_config = OpenStruct.new(definition[resource_definition_name.to_s])
      resource_set = instance_double(KubernetesTemplateRendering::ResourceSet)

      expect(resource_set).to receive(:render)
      expect(KubernetesTemplateRendering::ResourceSet).to receive(:new)
                             .with(config: expected_config, rendered_directory: rendered_directory, template_directory: template_directory, definitions_path: definitions_path, kubernetes_cluster_type: expected_kubernetes_cluster_type)
                             .and_return(resource_set)

      dir_renderer.render(args)
    end
  end
end
