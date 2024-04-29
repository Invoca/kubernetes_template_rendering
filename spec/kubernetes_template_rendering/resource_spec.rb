# frozen_string_literal: true

require_relative "../../lib/kubernetes_template_rendering/resource"
require_relative "../../lib/kubernetes_template_rendering/cli_arguments"

RSpec.describe KubernetesTemplateRendering::Resource do
  subject(:resource) do
    described_class.new(
      template_path: template_path,
      definitions_path: definitions_path,
      variables: variables,
      output_directory: output_directory,
      output_filename: output_filename
    )
  end
  let(:rendered_directory) { "zz-rendered" }
  let(:definitions_path) { "td/definitions.yaml" }
  let(:template_path) { "template-deploy.yaml.erb" }
  let(:variables) { { "a" => "1", "b" => "2" } }
  let(:output_directory) { "dir" }
  let(:jsonnet_library_path) { nil }
  let(:args) { KubernetesTemplateRendering::CLIArguments.new(rendered_directory, template_path, false, '', jsonnet_library_path) }

  before do
    stub_puts
    allow(File).to receive(:open).and_call_original
  end

  shared_examples "resource render" do
    it "writes the rendered template to the specified file" do
      template_output = "rendered output"
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render).with(template_path, variables, {jsonnet_library_path: jsonnet_library_path}).and_return(template_output)

      expect(File).to receive(:write).with("dir/#{expected_filename}", template_output)

      resource.render(args)
    end
  end

  context "when an output filename is provided" do
    let(:output_filename) { "out.txt" }
    let(:expected_filename) { output_filename }

    include_examples "resource render"
  end

  context "when an output filename is not provided" do
    let(:output_filename) { }
    let(:expected_filename) { "template-deploy.yaml" }

    include_examples "resource render"
  end
end
