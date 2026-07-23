# frozen_string_literal: true

require 'tmpdir'

require_relative "../../lib/kubernetes_template_rendering/resource_set"
require_relative "../../lib/kubernetes_template_rendering/cli_arguments"

RSpec.describe KubernetesTemplateRendering::ResourceSet do
  subject(:resource_set) do
    described_class.new(config: config,
                        rendered_directory: rendered_directory,
                        template_directory: template_directory,
                        definitions_path: definitions_path,
                        kubernetes_cluster_type: "prod")
  end
  let(:template_directory) { File.expand_path("../fixtures/resource_set", __dir__) }
  let(:definitions_path) { "td/definitions.yaml" }
  let(:rendered_directory) { Dir.mktmpdir }
  let(:directory_in_config) { "../some-cluster/%{plain_region}-render-here" }
  let(:deploy_groups) { ["primary", "secondary"] }
  let(:group_variable_name) { nil }
  let(:deploy_group_config) { nil }
  let(:omitted_resources) { nil }
  let(:variables) do
    {
      "a" => 1,
      "b" => "2",
      "c" => true
    }
  end
  let(:config) do
    {
      "directory" => directory_in_config,
      "deploy_groups" => deploy_group_config,
      "omitted_resources" => omitted_resources,
      "variables" => variables,
      "regions" => ["us-east-1"],
      "colors" => ["orange"]
    }
  end
  let(:output_directory_exists?) { true }
  let(:output_directory) { File.join(rendered_directory, directory_in_config) }
  let(:expanded_output_directory) { output_directory.sub("%{plain_region}", "us-east-1") }
  let(:args) { KubernetesTemplateRendering::CLIArguments.new(rendered_directory, template_directory, false, '') }

  before do
    stub_puts
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(expanded_output_directory).and_return(output_directory_exists?)
    allow(FileUtils).to receive(:mkdir_p).with(output_directory)
  end

  describe "output directory pattern resolution" do
    subject(:target_output_directory) do
      described_class.new(config: resolution_config,
                          rendered_directory: rendered_directory,
                          template_directory: template_directory,
                          definitions_path: definitions_path,
                          kubernetes_cluster_type: "prod",
                          spp: spp_value).target_output_directory
    end

    let(:spp_value) { false }
    let(:directory_value) { nil }
    let(:subdirectory_value) { nil }
    let(:resolution_config) do
      {
        "regions" => ["us-east-1"],
        "colors" => ["orange"]
      }.tap do |cfg|
        cfg["directory"]    = directory_value    if directory_value
        cfg["subdirectory"] = subdirectory_value if subdirectory_value
      end
    end

    context "with directory only" do
      let(:directory_value) { "custom/%{plain_region}/path" }

      it "uses the directory pattern verbatim" do
        expect(target_output_directory).to eq("custom/%{plain_region}/path")
      end
    end

    context "with subdirectory only" do
      let(:subdirectory_value) { "my-app" }

      it "builds the base path with the subdirectory appended" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}/my-app")
      end
    end

    context "with neither directory nor subdirectory" do
      it "uses the base path" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}")
      end
    end

    context "with both directory and subdirectory" do
      let(:directory_value) { "custom/%{plain_region}/path" }
      let(:subdirectory_value) { "my-app" }

      it "raises ArgumentError" do
        expect { target_output_directory }.to raise_error(ArgumentError, /only one of 'directory:' or 'subdirectory:'/)
      end
    end

    context "for an SPP definition with neither directory nor subdirectory" do
      let(:spp_value) { true }

      it "uses the SPP base path" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER")
      end
    end

    context "for an SPP definition with subdirectory only" do
      let(:spp_value) { true }
      let(:subdirectory_value) { "my-app" }

      it "appends the subdirectory under the SPP base path" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER/my-app")
      end
    end
  end

  describe "directory deprecation warning" do
    subject(:warnings) do
      captured = []
      allow_any_instance_of(described_class).to receive(:puts) { |_instance, *msgs| captured.concat(msgs) }
      described_class.new(config: warning_config,
                          rendered_directory: rendered_directory,
                          template_directory: template_directory,
                          definitions_path: definitions_path,
                          kubernetes_cluster_type: "prod",
                          spp: spp_value)
      captured.join("\n")
    end

    let(:directory_value) { nil }
    let(:subdirectory_value) { nil }
    let(:spp_value) { false }
    let(:warning_config) do
      {
        "regions" => ["us-east-1"],
        "colors" => ["orange"]
      }.tap do |cfg|
        cfg["directory"]    = directory_value    if directory_value
        cfg["subdirectory"] = subdirectory_value if subdirectory_value
      end
    end

    context "when directory is used with a non-standard layout" do
      let(:directory_value) { "../some-cluster/%{plain_region}-render-here" }

      it "warns that directory is deprecated" do
        expect(warnings).to include("`directory:` is deprecated")
      end
    end

    context "when directory is used with the standard layout" do
      let(:directory_value) { "%{plain_region}/%{type}/%{color}/staging-ops" }

      it "still warns that directory is deprecated" do
        expect(warnings).to include("`directory:` is deprecated")
      end
    end

    context "when subdirectory is used" do
      let(:subdirectory_value) { "my-app" }

      it "does not warn" do
        expect(warnings).to_not include("deprecated")
      end
    end

    context "when neither directory nor subdirectory is given" do
      it "does not warn" do
        expect(warnings).to_not include("deprecated")
      end
    end

    context "when directory is used by an SPP definition" do
      let(:spp_value) { true }
      let(:directory_value) { "custom/%{plain_region}/spp-path" }

      it "suggests the SPP base layout" do
        expect(warnings).to include("spp/SPP-PLACEHOLDER")
      end
    end
  end

  describe "rendering with subdirectory" do
    subject(:resource_set) do
      described_class.new(config: subdirectory_config,
                          rendered_directory: rendered_directory,
                          template_directory: template_directory,
                          definitions_path: definitions_path,
                          kubernetes_cluster_type: "prod")
    end
    let(:subdirectory_config) do
      {
        "subdirectory" => "my-app",
        "variables" => variables,
        "regions" => ["us-east-1"],
        "colors" => ["orange"]
      }
    end
    let(:expected_directory) { File.join(rendered_directory, "us-east-1", "prod", "orange", "my-app") }

    before do
      resource = instance_double(KubernetesTemplateRendering::Resource)
      allow(resource).to receive(:render)
      allow(KubernetesTemplateRendering::Resource).to receive(:new).and_return(resource)
      allow(File).to receive(:exist?).with(expected_directory).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
    end

    it "renders into region/cluster_type/color/subdirectory" do
      expect(FileUtils).to receive(:mkdir_p).with(expected_directory)
      resource_set.render(args)
    end
  end

  describe "output directory" do
    before do
      resource = instance_double(KubernetesTemplateRendering::Resource)
      allow(resource).to receive(:render)
      allow(KubernetesTemplateRendering::Resource).to receive(:new).and_return(resource)

      deploy_grouped = instance_double(KubernetesTemplateRendering::DeployGroupedResource)
      allow(deploy_grouped).to receive(:render)
      allow(KubernetesTemplateRendering::DeployGroupedResource).to receive(:new).and_return(deploy_grouped)
    end

    context "when it exists" do
      let(:output_directory_exists?) { true }

      it "does not create the directory" do
        expect(FileUtils).to_not receive(:mkdir_p)
        resource_set.render(args)
      end

      context "when the prune flag is set" do
        let(:args) { super().tap { _1.prune = true } }

        it "prunes the directory" do
          expect(FileUtils).to_not receive(:mkdir_p)
          expect(FileUtils).to receive(:rm_rf).with(expanded_output_directory)
          resource_set.render(args)
        end
      end
    end

    context "when it doesn't exist" do
      let(:output_directory_exists?) { false }

      it "creates the directory" do
        expect(FileUtils).to receive(:mkdir_p).with(expanded_output_directory)
        resource_set.render(args)
      end

      context "when the prune flag is set" do
        let(:args) { super().tap { _1.prune = false } }

        it "does not prune the directory" do
          expect(FileUtils).to receive(:mkdir_p).with(expanded_output_directory)
          expect(FileUtils).to_not receive(:rm_rf)
          resource_set.render(args)
        end
      end
    end
  end

  describe "#reconcile_scopes" do
    let(:config) do
      {
        "subdirectory" => "my-app",
        "variables" => variables,
        "regions" => ["us-east-1", "eu-central-1"],
        "colors" => ["orange"]
      }
    end

    it "roots the base at the canonical base path, for each region x color" do
      expect(resource_set.reconcile_scopes).to contain_exactly(
        { base_root: File.join(rendered_directory, "us-east-1", "prod", "orange"),    output_directory: File.join(rendered_directory, "us-east-1/prod/orange/my-app"),    spp: false, spp_base_root: File.join(rendered_directory, "us-east-1/prod/orange/spp/SPP-PLACEHOLDER") },
        { base_root: File.join(rendered_directory, "eu-central-1", "prod", "orange"), output_directory: File.join(rendered_directory, "eu-central-1/prod/orange/my-app"), spp: false, spp_base_root: File.join(rendered_directory, "eu-central-1/prod/orange/spp/SPP-PLACEHOLDER") }
      )
    end

    context "when the subdirectory nests more than one level deep" do
      let(:config) do
        {
          "subdirectory" => "exclude-argocd/my-app",
          "variables" => variables,
          "regions" => ["us-east-1"],
          "colors" => ["orange"]
        }
      end

      it "roots the base at the canonical base path, not the nested output parent" do
        expect(resource_set.reconcile_scopes).to contain_exactly(
          { base_root: File.join(rendered_directory, "us-east-1", "prod", "orange"), output_directory: File.join(rendered_directory, "us-east-1/prod/orange/exclude-argocd/my-app"), spp: false, spp_base_root: File.join(rendered_directory, "us-east-1/prod/orange/spp/SPP-PLACEHOLDER") }
        )
      end
    end

    context "for an SPP resource set" do
      subject(:resource_set) do
        described_class.new(config: config,
                            rendered_directory: rendered_directory,
                            template_directory: template_directory,
                            definitions_path: definitions_path,
                            kubernetes_cluster_type: "staging",
                            spp: true)
      end

      it "marks each scope as spp and carries the canonical spp_base_root, for each region x color" do
        expect(resource_set.reconcile_scopes).to contain_exactly(
          { base_root: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER"),    output_directory: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER/my-app"),    spp: true, spp_base_root: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER") },
          { base_root: File.join(rendered_directory, "eu-central-1/staging/orange/spp/SPP-PLACEHOLDER"), output_directory: File.join(rendered_directory, "eu-central-1/staging/orange/spp/SPP-PLACEHOLDER/my-app"), spp: true, spp_base_root: File.join(rendered_directory, "eu-central-1/staging/orange/spp/SPP-PLACEHOLDER") }
        )
      end

      context "when the subdirectory nests more than one level deep" do
        let(:config) do
          {
            "subdirectory" => "exclude-argocd/my-app",
            "variables" => variables,
            "regions" => ["us-east-1"],
            "colors" => ["orange"]
          }
        end

        it "roots the base at the canonical spp/SPP-PLACEHOLDER path, not the nested output parent" do
          expect(resource_set.reconcile_scopes).to contain_exactly(
            { base_root: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER"), output_directory: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER/exclude-argocd/my-app"), spp: true, spp_base_root: File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER") }
          )
        end
      end
    end

    context "when a legacy directory: pattern renders outside the canonical layout (e.g. <region>/<service>)" do
      # The deprecated `directory:` field is the only way to express a non-canonical layout. The base
      # root is always the canonical base path regardless; the renderer's --reconcile guard rejects an
      # entry whose output falls outside that root (see template_directory_renderer_spec).
      let(:config) do
        {
          "directory" => "%{plain_region}/transaction-events",
          "variables" => variables,
          "regions" => ["us-east-1", "eu-central-1"],
          "colors" => ["orange"]
        }
      end

      it "roots the base at the canonical base path, independent of the directory: output" do
        expect(resource_set.reconcile_scopes).to contain_exactly(
          { base_root: File.join(rendered_directory, "us-east-1", "prod", "orange"),    output_directory: File.join(rendered_directory, "us-east-1/transaction-events"),    spp: false, spp_base_root: File.join(rendered_directory, "us-east-1/prod/orange/spp/SPP-PLACEHOLDER") },
          { base_root: File.join(rendered_directory, "eu-central-1", "prod", "orange"), output_directory: File.join(rendered_directory, "eu-central-1/transaction-events"), spp: false, spp_base_root: File.join(rendered_directory, "eu-central-1/prod/orange/spp/SPP-PLACEHOLDER") }
        )
      end
    end

    it "does not mutate variables" do
      expect { resource_set.reconcile_scopes }.to_not(change { resource_set.variables })
    end
  end

  describe "render" do
    def expand_paths(paths)
      paths.map { |path| File.expand_path(File.join(template_directory, path)) }
    end

    shared_examples "render" do
      it "renders the resources" do
        standard = expand_paths(standard_resources)
        deploy_grouped = expand_paths(deploy_grouped_resources)

        standard.each do |path|
          resource = instance_double(KubernetesTemplateRendering::Resource)
          expect(KubernetesTemplateRendering::Resource).to receive(:new)
                                .with(template_path: path, definitions_path: definitions_path, variables: variables, output_directory: expanded_output_directory, variable_overrides: {}, source_repo: nil)
                                .and_return(resource)
          expect(resource).to receive(:render)
        end

        deploy_grouped.each do |path|
          deploy_grouped_resource = instance_double(KubernetesTemplateRendering::DeployGroupedResource)
          expect(KubernetesTemplateRendering::DeployGroupedResource).to receive(:new)
                                             .with(
                                               template_path: path,
                                               definitions_path: definitions_path,
                                               variables: variables,
                                               output_directory: expanded_output_directory,
                                               groups_to_render: deploy_groups,
                                               template_path_exclusions: nil,
                                               group_variable_name: group_variable_name,
                                               variable_overrides: {},
                                               source_repo: nil
                                             )
                                             .and_return(deploy_grouped_resource)
          expect(deploy_grouped_resource).to receive(:render)
        end

        resource_set.render(args)
      end
    end

    context "when deploy groups are configured with specific files" do
      let(:standard_resources) { ["app-svc.yaml.erb", "app-namespace.jsonnet"] }
      let(:deploy_grouped_resources) { ["app-deploy.yaml.erb", "app-cm.yaml.erb"] }
      let(:deploy_group_config) do
        {
          "files" => deploy_grouped_resources,
          "group_names" => deploy_groups
        }
      end

      include_examples "render"
    end

    context "when deploy groups are configured but without specific files" do
      let(:standard_resources) { ["app-svc.yaml.erb", "app-cm.yaml.erb", "app-namespace.jsonnet"] }
      let(:deploy_grouped_resources) { ["app-deploy.yaml.erb"] }
      let(:deploy_group_config) { { "group_names" => deploy_groups } }

      include_examples "render"
    end

    context "when deploy groups are configured with group_variable_name" do
      let(:standard_resources) { ["app-svc.yaml.erb", "app-cm.yaml.erb", "app-namespace.jsonnet"] }
      let(:deploy_grouped_resources) { ["app-deploy.yaml.erb"] }
      let(:group_variable_name) { "owner" }
      let(:deploy_group_config) { { "group_names" => deploy_groups, "variable_name" => group_variable_name } }

      include_examples "render"
    end

    context "when deploy groups are configured with array of group names" do
      let(:standard_resources) { ["app-svc.yaml.erb", "app-cm.yaml.erb", "app-namespace.jsonnet"] }
      let(:deploy_grouped_resources) { ["app-deploy.yaml.erb"] }
      let(:deploy_groups) { ["call-imports-primary", "call-imports-secondary", "signal-primary", "signal-secondary"] }
      let(:deploy_group_config) { { "group_names" => [["call-imports", "signal"], ["primary", "secondary"]] } }

      include_examples "render"
    end

    context "when deploy groups aren't configured" do
      let(:standard_resources) do
        [
          "app-svc.yaml.erb",
          "app-cm.yaml.erb",
          "app-deploy.yaml.erb",
          "app-namespace.jsonnet"
        ]
      end
      let(:deploy_grouped_resources) { [] }
      let(:deploy_group_config) { nil }

      include_examples "render"
    end

    context "when resources are omitted" do
      let(:standard_resources) { ["app-deploy.yaml.erb", "app-namespace.jsonnet"] }
      let(:deploy_grouped_resources) { [] }
      let(:deploy_group_config) { nil }
      let(:omitted_resources) { ["app-svc.yaml.erb", "app-cm.yaml.erb"] }

      include_examples "render"
    end

    context "when variable_overrides and source_repo are provided" do
      subject(:resource_set) do
        described_class.new(
          config: config,
          rendered_directory: rendered_directory,
          template_directory: template_directory,
          definitions_path: definitions_path,
          kubernetes_cluster_type: "prod",
          variable_overrides: { "deploySha" => "abc123" },
          source_repo: "Invoca/web"
        )
      end

      let(:deploy_group_config) { { "group_names" => deploy_groups } }

      it "forwards variable_overrides and source_repo to DeployGroupedResource" do
        path = File.expand_path(File.join(template_directory, "app-deploy.yaml.erb"))
        deploy_grouped_resource = instance_double(KubernetesTemplateRendering::DeployGroupedResource)
        allow(KubernetesTemplateRendering::Resource).to receive(:new).and_return(instance_double(KubernetesTemplateRendering::Resource, render: nil))

        expect(KubernetesTemplateRendering::DeployGroupedResource).to receive(:new)
          .with(
            template_path: path,
            definitions_path: definitions_path,
            variables: variables,
            output_directory: expanded_output_directory,
            groups_to_render: deploy_groups,
            template_path_exclusions: nil,
            group_variable_name: nil,
            variable_overrides: { "deploySha" => "abc123" },
            source_repo: "Invoca/web"
          )
          .and_return(deploy_grouped_resource)
        expect(deploy_grouped_resource).to receive(:render)

        resource_set.render(args)
      end
    end
  end

  describe "SPP placeholder expansion" do
    let(:rendered_directory) { Dir.mktmpdir }
    let(:template_directory) { Dir.mktmpdir }

    before do
      allow(FileUtils).to receive(:mkdir_p).and_call_original
      allow(File).to receive(:exist?).and_call_original
    end

    let(:config) do
      {
        "directory" => "%{plain_region}/staging/%{color}/spp/SPP-PLACEHOLDER-telephony",
        "regions" => ["us-east-1"],
        "colors" => ["orange"],
        "variables" => { "namespace" => "SPP-PLACEHOLDER-telephony" }
      }
    end
    let(:args) { KubernetesTemplateRendering::CLIArguments.new.tap { |a| a.fork = false } }

    after do
      FileUtils.rm_rf(rendered_directory)
      FileUtils.rm_rf(template_directory)
    end

    it "calls PlaceholderExpander once per SPP for the rendered output directory" do
      resource_set = described_class.new(
        config: config,
        template_directory: template_directory,
        rendered_directory: rendered_directory,
        definitions_path: File.join(template_directory, "definitions.yaml"),
        kubernetes_cluster_type: "staging",
        spp: true,
        spps: ["staging-qa02a", "staging-qa08a"]
      )

      expected_output_directory = File.join(rendered_directory, "us-east-1/staging/orange/spp/SPP-PLACEHOLDER-telephony")
      allow(resource_set).to receive(:resources).and_return([])
      allow(resource_set).to receive(:puts)

      expect(KubernetesTemplateRendering::PlaceholderExpander).to receive(:expand!)
        .with(source_directory: expected_output_directory, target_name: "staging-qa02a", placeholder_token: "SPP-PLACEHOLDER")
      expect(KubernetesTemplateRendering::PlaceholderExpander).to receive(:expand!)
        .with(source_directory: expected_output_directory, target_name: "staging-qa08a", placeholder_token: "SPP-PLACEHOLDER")

      resource_set.render(args)
    end

    it "with --prune, wipes each per-SPP destination directory before expansion" do
      resource_set = described_class.new(
        config: config,
        template_directory: template_directory,
        rendered_directory: rendered_directory,
        definitions_path: File.join(template_directory, "definitions.yaml"),
        kubernetes_cluster_type: "staging",
        spp: true,
        spps: ["staging-qa02a"]
      )

      args.prune = true
      per_spp_dest = File.join(rendered_directory, "us-east-1/staging/orange/spp/staging-qa02a-telephony")
      FileUtils.mkdir_p(per_spp_dest)
      stale_file = File.join(per_spp_dest, "stale.yaml")
      File.write(stale_file, "old: data\n")

      allow(resource_set).to receive(:resources).and_return([])
      allow(resource_set).to receive(:puts)
      allow(KubernetesTemplateRendering::PlaceholderExpander).to receive(:expand!)

      resource_set.render(args)

      expect(File.exist?(stale_file)).to be(false)
    end

    it "does not call PlaceholderExpander when spp is false" do
      resource_set = described_class.new(
        config: config.merge("directory" => "%{plain_region}/%{type}/%{color}/production"),
        template_directory: template_directory,
        rendered_directory: rendered_directory,
        definitions_path: File.join(template_directory, "definitions.yaml"),
        kubernetes_cluster_type: "prod",
        spp: false,
        spps: []
      )

      allow(resource_set).to receive(:resources).and_return([])
      allow(resource_set).to receive(:puts)

      expect(KubernetesTemplateRendering::PlaceholderExpander).not_to receive(:expand!)
      resource_set.render(args)
    end
  end

  describe "nested MULTI_FILE_RENDER path keys" do
    let(:template_directory) { Dir.mktmpdir }
    let(:rendered_directory) { Dir.mktmpdir }
    let(:definitions_path) { File.join(template_directory, "definitions.yaml") }
    let(:nested_fixture) { File.expand_path("../fixtures/jsonnet/nested_path_multi_file_example.jsonnet", __dir__) }
    let(:args) { KubernetesTemplateRendering::CLIArguments.new(rendered_directory, template_directory, false, '') }

    before do
      stub_puts
      allow(FileUtils).to receive(:mkdir_p).and_call_original
      allow(File).to receive(:exist?).and_call_original
      FileUtils.cp(nested_fixture, File.join(template_directory, "nested.jsonnet"))
      File.write(
        definitions_path,
        {
          "staging" => {
            "regions" => ["us-east-1"],
            "colors" => ["orange"],
            "variables" => { "name" => "pnapi" }
          }
        }.to_yaml
      )
    end

    after do
      FileUtils.remove_entry(template_directory)
      FileUtils.remove_entry(rendered_directory)
    end

    it "writes nested paths under the standard region/cluster_type/color base" do
      resource_set = described_class.new(
        config: { "regions" => ["us-east-1"], "colors" => ["orange"], "variables" => { "name" => "pnapi" } },
        rendered_directory: rendered_directory,
        template_directory: template_directory,
        definitions_path: definitions_path,
        kubernetes_cluster_type: "staging"
      )

      resource_set.render(args)

      base = File.join(rendered_directory, "us-east-1", "staging", "orange")
      expect(File.read(File.join(base, "pr-1/app/service.yaml"))).to include("pnapi-service")
      expect(File.read(File.join(base, "pr-1/mysql/pnapi-database.yaml"))).to include("kind: Deployment")
    end
  end
end
