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

  {
    "test"               => { cluster_type: "test",    spp: false },
    "prod.gcp"           => { cluster_type: "prod",    spp: false },
    "staging"            => { cluster_type: "staging", spp: false },
    "SPP-PLACEHOLDER"    => { cluster_type: "staging", spp: true },
    "SPP-PLACEHOLDER.eu" => { cluster_type: "staging", spp: true }
  }.each do |resource_definition_name, expected|
    it "builds a ResourceSet with an appropriate kubernetes_cluster_type for each directory and calls render on it" do
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
            variable_overrides: {},
            source_repo: nil
          )
          .and_return(resource_set)
      )

      dir_renderer.render(args)
    end
  end

  describe "reconcile sweep" do
    let(:reconcile_args) do
      KubernetesTemplateRendering::CLIArguments.new(rendered_directory, template_directory, false, '').tap { _1.reconcile = true }
    end

    before do
      stub_puts(KubernetesTemplateRendering::ResourceSet)
      stub_puts(KubernetesTemplateRendering::Resource)
      stub_puts(KubernetesTemplateRendering::Reconciler)
    end

    def write_template_dir(entries)
      File.write(File.join(template_directory, "app.yaml.erb"), "kind: Test\nname: app\n")
      definitions = entries.transform_values do |dir|
        { "directory" => dir, "regions" => ["local"], "colors" => ["orange"], "variables" => {} }
      end
      File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definitions.to_yaml)
    end

    def render!
      described_class.new(directories: [template_directory], rendered_directory: rendered_directory).render(reconcile_args)
    end

    def age(path)
      File.utime(Time.now - 3600, Time.now - 3600, path)
    end

    it "removes the directory of a deleted entry while keeping freshly-rendered output (AC 1)" do
      write_template_dir("test" => "%{plain_region}/%{type}/%{color}/app-a")
      base = File.join(rendered_directory, "local/test/orange")
      stale_dir = File.join(base, "app-b")
      stale_file = File.join(stale_dir, "old.yaml")
      FileUtils.mkdir_p(stale_dir)
      File.write(stale_file, "stale")
      age(stale_file)

      render!

      expect(File.exist?(File.join(base, "app-a", "app.yaml"))).to be(true)
      expect(File.exist?(stale_file)).to be(false)
      expect(File.directory?(stale_dir)).to be(false)
    end

    it "produces identical results across two consecutive reconcile renders (AC 3)" do
      write_template_dir("test" => "%{plain_region}/%{type}/%{color}/app-a")

      render!
      first = Dir.glob(File.join(rendered_directory, "**", "*")).sort
      render!
      second = Dir.glob(File.join(rendered_directory, "**", "*")).sort

      expect(second).to eq(first)
    end

    it "hard-errors and deletes nothing when an entry path escapes its scope prefix (AC 4)" do
      write_template_dir("test" => "../outside/%{plain_region}/%{type}/%{color}/app")
      preexisting = File.join(rendered_directory, "local/test/orange/keep.yaml")
      FileUtils.mkdir_p(File.dirname(preexisting))
      File.write(preexisting, "keep")
      age(preexisting)

      expect { render! }.to raise_error(KubernetesTemplateRendering::Reconciler::OutOfScopeError)
      expect(File.exist?(preexisting)).to be(true)
    end

    it "fences spp/ subtrees out of the base sweep (deleted-SPP cleanup stays manual)" do
      write_template_dir("test" => "%{plain_region}/%{type}/%{color}/app-a")
      spp_file = File.join(rendered_directory, "local/test/orange/spp/qa02a/old.yaml")
      FileUtils.mkdir_p(File.dirname(spp_file))
      File.write(spp_file, "spp")
      age(spp_file)

      render!

      expect(File.exist?(spp_file)).to be(true)
    end

    it "does not sweep an SPP entry whose directory renders into spp/<spp-name>" do
      write_template_dir("SPP-PLACEHOLDER" => "%{plain_region}/staging/%{color}/spp/SPP-PLACEHOLDER")
      stale_spp_file = File.join(rendered_directory, "local/staging/orange/spp/SPP-PLACEHOLDER/old.yaml")
      FileUtils.mkdir_p(File.dirname(stale_spp_file))
      File.write(stale_spp_file, "stale")
      age(stale_spp_file)

      render!

      expect(File.exist?(stale_spp_file)).to be(true)
    end
  end
end
