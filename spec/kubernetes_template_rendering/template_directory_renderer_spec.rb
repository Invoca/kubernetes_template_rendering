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

    # Each entry maps a definition name to an optional `subdirectory:` segment (nil -> the derived
    # base path). Names containing SPP-PLACEHOLDER derive the `.../spp/SPP-PLACEHOLDER` base. This
    # deliberately avoids the deprecated `directory:` field so the specs exercise supported layouts.
    def write_template_dir(entries, region: "us-east-1")
      File.write(File.join(template_directory, "app.yaml.erb"), "kind: Test\nname: app\n")
      definitions = entries.transform_values do |subdirectory|
        cfg = { "regions" => [region], "colors" => ["orange"], "variables" => {} }
        cfg["subdirectory"] = subdirectory if subdirectory
        cfg
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
      # my-app is still rendered; deleted-app is the leftover output of an entry removed upstream.
      write_template_dir({ "prod" => "my-app" }, region: "us-east-1")
      base = File.join(rendered_directory, "us-east-1/prod/orange")
      stale_dir = File.join(base, "deleted-app")
      stale_file = File.join(stale_dir, "deployment.yaml")
      FileUtils.mkdir_p(stale_dir)
      File.write(stale_file, "stale")
      age(stale_file)

      render!

      expect(File.exist?(File.join(base, "my-app", "app.yaml"))).to be(true)
      expect(File.exist?(stale_file)).to be(false)
      expect(File.directory?(stale_dir)).to be(false)
    end

    it "produces identical results across two consecutive reconcile renders (AC 3)" do
      write_template_dir({ "prod" => "my-app" }, region: "us-east-1")

      render!
      first = Dir.glob(File.join(rendered_directory, "**", "*")).sort
      render!
      second = Dir.glob(File.join(rendered_directory, "**", "*")).sort

      expect(second).to eq(first)
    end

    it "hard-errors and deletes nothing when an entry path escapes its scope prefix (AC 4)" do
      # An out-of-prefix scope is only reachable through the deprecated `directory:` escape hatch
      # (subdirectory/base paths are always rooted under region/type/color), so this test must use
      # `directory:` to exercise the guard that defends against exactly that footgun.
      File.write(File.join(template_directory, "app.yaml.erb"), "kind: Test\nname: app\n")
      definitions = {
        "prod" => { "directory" => "../outside/%{plain_region}/%{type}/%{color}/app", "regions" => ["us-east-1"], "colors" => ["orange"], "variables" => {} }
      }
      File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definitions.to_yaml)
      preexisting = File.join(rendered_directory, "us-east-1/prod/orange/keep.yaml")
      FileUtils.mkdir_p(File.dirname(preexisting))
      File.write(preexisting, "keep")
      age(preexisting)

      expect { render! }.to raise_error(KubernetesTemplateRendering::Reconciler::OutOfScopeError)
      expect(File.exist?(preexisting)).to be(true)
    end

    it "fences spp/ subtrees out of the base sweep (deleted-SPP cleanup stays manual)" do
      # A non-SPP staging entry (named "staging" -> cluster_type staging, spp: false) coexists with a
      # real SPP instance under the same region/type/color. The base sweep must not touch the spp/ tree.
      write_template_dir({ "staging" => "my-app" }, region: "us-east-1")
      spp_file = File.join(rendered_directory, "us-east-1/staging/orange/spp/staging-qa02a/my-app/old.yaml")
      FileUtils.mkdir_p(File.dirname(spp_file))
      File.write(spp_file, "spp")
      age(spp_file)

      render!

      expect(File.exist?(spp_file)).to be(true)
    end

    it "sweeps stale files inside a rendered SPP entry's own directory" do
      write_template_dir({ "SPP-PLACEHOLDER" => nil }, region: "us-east-1")
      stale_spp_file = File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER/old.yaml")
      FileUtils.mkdir_p(File.dirname(stale_spp_file))
      File.write(stale_spp_file, "stale")
      age(stale_spp_file)

      render!

      expect(File.exist?(stale_spp_file)).to be(false)
    end

    it "sweeps stale files inside the rendered SPP directory while leaving non-rendered sibling SPP directories untouched (TEST CASE 2)" do
      write_template_dir({ "SPP-PLACEHOLDER" => "my-app" }, region: "us-east-1")
      spp_base         = File.join(rendered_directory, "us-east-1/staging/orange/spp")
      stale_file       = File.join(spp_base, "SPP-PLACEHOLDER/my-app/old.yaml")
      sibling_spp_file = File.join(spp_base, "staging-qa02a/my-app/kept.yaml")
      FileUtils.mkdir_p(File.dirname(stale_file))
      FileUtils.mkdir_p(File.dirname(sibling_spp_file))
      File.write(stale_file, "stale")
      File.write(sibling_spp_file, "kept")
      age(stale_file)
      age(sibling_spp_file)

      render!

      expect(File.exist?(stale_file)).to be(false)       # swept inside rendered SPP
      expect(File.exist?(sibling_spp_file)).to be(true)  # non-rendered sibling untouched
    end

    # End-to-end TEST CASE 2: a real SPP definition (name contains SPP-PLACEHOLDER, no deprecated
    # `directory:`) renders into the derived `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER`
    # base path. Without --spp, deleting templates/frontend/frontend-cm.yaml.erb upstream and
    # re-rendering with --reconcile must delete only the SPP-PLACEHOLDER stale file, re-render the
    # surviving resource, and leave the expanded SPP instances (staging-qa02a, staging-qa10a) untouched.
    it "deletes only the SPP-PLACEHOLDER stale file and leaves expanded SPP instances untouched (TEST CASE 2, derived SPP path)" do
      # frontend-cm.yaml.erb was deleted upstream; only the servicemonitor template remains to render.
      File.write(File.join(template_directory, "frontend-prometheus-servicemonitor.yaml.erb"), "kind: ServiceMonitor\n")
      definitions = {
        "SPP-PLACEHOLDER" => { "subdirectory" => "frontend", "regions" => ["us-east-1"], "colors" => ["orange"], "variables" => {} }
      }
      File.write(File.join(template_directory, described_class::DEFINITIONS_FILENAME), definitions.to_yaml)

      spp_root             = File.join(rendered_directory, "us-east-1/staging/orange/spp")
      placeholder_frontend = File.join(spp_root, "SPP-PLACEHOLDER/frontend")
      stale_cm             = File.join(placeholder_frontend, "frontend-cm.yaml") # template deleted upstream -> stale
      expanded_instances   = %w[staging-qa02a staging-qa10a].flat_map do |spp|
        %w[frontend-cm.yaml frontend-prometheus-servicemonitor.yaml].map { |f| File.join(spp_root, spp, "frontend", f) }
      end

      ([stale_cm] + expanded_instances).each do |f|
        FileUtils.mkdir_p(File.dirname(f))
        File.write(f, "old")
        age(f)
      end

      described_class.new(
        directories: [template_directory],
        rendered_directory: rendered_directory,
        cluster_type: "staging",
        region: "us-east-1",
        color: "orange"
      ).render(reconcile_args)

      expect(File.exist?(stale_cm)).to be(false) # stale SPP-PLACEHOLDER resource swept
      expect(File.exist?(File.join(placeholder_frontend, "frontend-prometheus-servicemonitor.yaml"))).to be(true) # re-rendered
      expanded_instances.each { |f| expect(File.exist?(f)).to be(true) } # expanded SPP instances untouched
    end
  end
end
