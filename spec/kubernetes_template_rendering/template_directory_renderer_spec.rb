# frozen_string_literal: true

require 'tmpdir'

require_relative "../../lib/kubernetes_template_rendering/template_directory_renderer"
require_relative "../../lib/kubernetes_template_rendering/cli_arguments"

RSpec.describe KubernetesTemplateRendering::TemplateDirectoryRenderer do
  subject(:dir_renderer) { described_class.new(directories: [template_directory], rendered_directory: rendered_directory, spps: spps) }
  let(:spps) { ["staging-qa02a"] }
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

  {
    "test"               => { cluster_type: "test",    spp: false },
    "prod.gcp"           => { cluster_type: "prod",    spp: false },
    "staging"            => { cluster_type: "staging", spp: false },
    "SPP-PLACEHOLDER"    => { cluster_type: "staging", spp: true },
    "SPP-PLACEHOLDER.eu" => { cluster_type: "staging", spp: true }
  }.each do |resource_definition_name, expected|
    it "builds a ResourceSet with spp=#{expected[:spp].inspect} and the right cluster_type for #{resource_definition_name}" do
      definition = build_definition(name: resource_definition_name, rendered_directory: rendered_directory, template_directory: template_directory, variables: variables)
      definitions_path = File.join(template_directory, described_class::DEFINITIONS_FILENAME)
      File.write(definitions_path, definition.to_yaml)

      expected_config = OpenStruct.new(definition[resource_definition_name])
      resource_set = instance_double(KubernetesTemplateRendering::ResourceSet)

      expect(resource_set).to receive(:render)
      expect(KubernetesTemplateRendering::ResourceSet).to(
        receive(:new)
          .with(
            config: expected_config,
            rendered_directory: rendered_directory,
            template_directory: template_directory,
            definitions_path: definitions_path,
            kubernetes_cluster_type: expected[:cluster_type],
            spp: expected[:spp],
            spps: spps,
            variable_overrides: {},
            source_repo: nil
          )
          .and_return(resource_set)
      )

      dir_renderer.render(args)
    end
  end

  it "with --only, builds ResourceSets only for matching entries" do
    definition = {
      "staging" => { "directory" => "%{plain_region}/staging/orange/sample-app", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] },
      "staging.test" => { "directory" => "%{plain_region}/staging/orange/sample-app-test", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] }
    }
    File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definition.to_yaml)

    renderer = described_class.new(
      directories: [template_directory],
      rendered_directory: rendered_directory,
      only: ["staging.test"]
    )

    resource_set = instance_double(KubernetesTemplateRendering::ResourceSet)
    allow(resource_set).to receive(:render)
    allow(KubernetesTemplateRendering::ResourceSet).to receive(:new).and_return(resource_set)

    renderer.render(args)

    expect(KubernetesTemplateRendering::ResourceSet).to have_received(:new).once
    expect(KubernetesTemplateRendering::ResourceSet).to have_received(:new).with(
      hash_including(config: have_attributes(directory: "%{plain_region}/staging/orange/sample-app-test"))
    )
  end

  it "raises an error when an --only value matches no entry across any definitions.yaml" do
    definition = {
      "staging" => { "directory" => "%{plain_region}/staging/orange/sample-app", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] }
    }
    File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definition.to_yaml)

    renderer = described_class.new(
      directories: [template_directory],
      rendered_directory: rendered_directory,
      only: ["staging.test"]
    )

    expect { renderer.render(args) }.to raise_error(ArgumentError, /--only values not found.*staging\.test/)
  end

  it "does not raise when every --only value matches at least one entry" do
    definition = {
      "staging" => { "directory" => "%{plain_region}/staging/orange/sample-app", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] },
      "staging.test" => { "directory" => "%{plain_region}/staging/orange/sample-app-test", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] }
    }
    File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definition.to_yaml)

    renderer = described_class.new(
      directories: [template_directory],
      rendered_directory: rendered_directory,
      only: ["staging", "staging.test"]
    )

    resource_set = instance_double(KubernetesTemplateRendering::ResourceSet)
    allow(resource_set).to receive(:render)
    allow(KubernetesTemplateRendering::ResourceSet).to receive(:new).and_return(resource_set)

    expect { renderer.render(args) }.not_to raise_error
  end

  it "with --only and --prune, prunes only the filtered entries' destinations and leaves siblings untouched" do
    definition = {
      "staging" => { "directory" => "%{plain_region}/staging/orange/sample-app", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] },
      "staging.test" => { "directory" => "%{plain_region}/staging/orange/sample-app-test", "variables" => variables, "regions" => ["us-east-1"], "colors" => ["orange"] }
    }
    File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definition.to_yaml)

    staging_dest = File.join(rendered_directory, "us-east-1/staging/orange/sample-app")
    staging_test_dest = File.join(rendered_directory, "us-east-1/staging/orange/sample-app-test")
    FileUtils.mkdir_p(staging_dest)
    FileUtils.mkdir_p(staging_test_dest)

    renderer = described_class.new(
      directories: [template_directory],
      rendered_directory: rendered_directory,
      only: ["staging.test"]
    )

    args.prune = true

    allow(FileUtils).to receive(:rm_rf).and_call_original

    renderer.render(args)

    expect(FileUtils).to have_received(:rm_rf).with(staging_test_dest)
    expect(FileUtils).not_to have_received(:rm_rf).with(staging_dest)
    expect(File.exist?(staging_dest)).to be(true)
  end
end
