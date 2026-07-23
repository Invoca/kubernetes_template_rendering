# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render).with(template_path, variables, jsonnet_library_path: jsonnet_library_path, variable_overrides: {}, source_repo: nil).and_return(template_output)

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

  context "when a multi-file template returns nested path keys" do
    subject(:resource) do
      described_class.new(
        template_path: template_path,
        definitions_path: definitions_path,
        variables: variables,
        output_directory: output_directory
      )
    end
    let(:output_directory) { Dir.mktmpdir }

    after { FileUtils.remove_entry(output_directory) }

    it "creates intermediate directories and writes nested and flat files" do
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "pr-1/app/foo.yaml" => "nested contents", "bar.yaml" => "flat contents" })

      resource.render(args)

      expect(File.read(File.join(output_directory, "pr-1/app/foo.yaml"))).to eq("nested contents")
      expect(File.read(File.join(output_directory, "bar.yaml"))).to eq("flat contents")
    end

    it "raises when a filename escapes the output directory" do
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "../evil.yaml" => "contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
    end

    it "raises when a filename traverses a symlink inside the output directory" do
      outside_directory = Dir.mktmpdir
      symlink_name = "evil_link"
      File.symlink(outside_directory, File.join(output_directory, symlink_name))

      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "#{symlink_name}/pwned.yaml" => "escaped contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
      expect(Dir.glob(File.join(outside_directory, "**", "*"))).to be_empty
    ensure
      FileUtils.remove_entry(outside_directory) if outside_directory
    end

    it "raises when a filename is exactly '..'" do
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ ".." => "contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
    end

    it "neutralizes an absolute-looking filename by nesting it under the output directory" do
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "/etc/passwd" => "not actually /etc/passwd" })

      resource.render(args)

      expect(File.read(File.join(output_directory, "etc/passwd"))).to eq("not actually /etc/passwd")
      expect(File.exist?("/etc/passwd_should_never_be_written")).to be false
    end

    it "writes deeply nested paths" do
      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "a/b/c/d/e/f.yaml" => "deep contents" })

      resource.render(args)

      expect(File.read(File.join(output_directory, "a/b/c/d/e/f.yaml"))).to eq("deep contents")
    end

    it "raises when a symlink is several directory levels deep, not the immediate child" do
      outside_directory = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(output_directory, "a", "b"))
      File.symlink(outside_directory, File.join(output_directory, "a", "b", "evil_link"))

      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "a/b/evil_link/pwned.yaml" => "escaped contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
      expect(Dir.glob(File.join(outside_directory, "**", "*"))).to be_empty
    ensure
      FileUtils.remove_entry(outside_directory) if outside_directory
    end

    it "raises for a dangling symlink (target does not exist) inside the output directory" do
      File.symlink("/tmp/does-not-exist-anywhere-xyz", File.join(output_directory, "dangling_link"))

      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "dangling_link/pwned.yaml" => "escaped contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
    end

    it "raises for a chain of symlinks (symlink -> symlink -> outside)" do
      outside_directory = Dir.mktmpdir
      link2 = File.join(output_directory, "link2")
      link1 = File.join(output_directory, "link1")
      File.symlink(outside_directory, link2)
      File.symlink(link2, link1)

      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "link1/pwned.yaml" => "escaped contents" })

      expect { resource.render(args) }.to raise_error(ArgumentError, /escapes output directory/)
      expect(Dir.glob(File.join(outside_directory, "**", "*"))).to be_empty
    ensure
      FileUtils.remove_entry(outside_directory) if outside_directory
    end

    it "still writes correctly when output_directory itself is reached via a symlink" do
      real_target = Dir.mktmpdir
      symlinked_output_directory = File.join(Dir.mktmpdir, "symlinked_output")
      File.symlink(real_target, symlinked_output_directory)
      symlinked_resource = described_class.new(
        template_path: template_path,
        definitions_path: definitions_path,
        variables: variables,
        output_directory: symlinked_output_directory
      )

      expect(KubernetesTemplateRendering::ErbTemplate).to receive(:render)
        .and_return({ "pr-1/app/foo.yaml" => "nested via symlinked base" })

      symlinked_resource.render(args)

      expect(File.read(File.join(real_target, "pr-1/app/foo.yaml"))).to eq("nested via symlinked base")
    ensure
      FileUtils.remove_entry(real_target) if real_target
      FileUtils.remove_entry(File.dirname(symlinked_output_directory)) if symlinked_output_directory
    end
  end
end
