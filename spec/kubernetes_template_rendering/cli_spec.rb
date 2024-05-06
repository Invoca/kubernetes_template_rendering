# frozen_string_literal: true

require 'tmpdir'

require_relative "../../lib/kubernetes_template_rendering/cli"

RSpec.describe KubernetesTemplateRendering::CLI do
  subject(:cli) do
    described_class.send(:parse, options).first
  rescue SystemExit => ex
    if expect_system_exit
      raise
    else
      raise "Unexpected SystemExit: #{ex}"
    end
  end

  let(:render_option) { "--render-directory=#{render_directory}" }
  let(:templates_directory) { "/tmp/templates" }
  let(:template_directory_option) { File.join(templates_directory, "tts-service") }
  let(:help_option) { "--help" }
  let(:platform_name) { "staging-test" }
  let(:render_directory) { Dir.mktmpdir }
  let(:expect_system_exit) { false }

  before do
    stub_const("ARGV", options)
    allow(described_class).to receive(:puts)
    FileUtils.rm_rf(templates_directory)
    Dir.mkdir(templates_directory)
  end

  context "when neither required options is provided" do
    let(:expect_system_exit) { true }
    let(:options) { [] }

    it "exits" do
      expect(STDERR).to receive(:puts)
      expect { cli }.to raise_exception(SystemExit)
    end
  end

  context "when the help option is passed" do
    let(:expect_system_exit) { true }
    let(:options) { [help_option] }

    it "exits" do
      expect { cli }.to raise_exception(SystemExit)
    end
  end

  describe "multi-directory options" do
    let(:directories_with_definitions) { 3.times.map { |i| "dir#{i}" } }
    let(:no_definition_directories) { 2.times.map { |i| "empty#{i}" } }
    let(:expected_directories) { directories_with_definitions.map { |dir| File.join(templates_directory, dir) } }

    before do
      directories_with_definitions.each do |name|
        path = File.join(templates_directory, name)
        FileUtils.mkdir(path)
        FileUtils.touch(File.join(path, described_class::DEFINITIONS_FILENAME))
      end

      no_definition_directories.each do |name|
        path = File.join(templates_directory, name)
        FileUtils.mkdir(path)
      end
    end

    context "when the root templates folder is passed" do
      let(:options) { [render_option, templates_directory] }
      let(:expected_directories) { directories_with_definitions.map { |dir| File.join(templates_directory, dir) } }

      it "returns a configured TemplateDirectoryRenderer" do
        expect(cli).to be_a(KubernetesTemplateRendering::TemplateDirectoryRenderer)
        expect(cli.directories.sort).to eq(expected_directories.sort)
        expect(cli.rendered_directory).to eq(render_directory)
      end
    end
  end

  context "when a template directory name is passed" do
    let(:options) { [render_option, template_directory_option] }

    context "and directory exists" do
      before do
        FileUtils.mkdir(template_directory_option) rescue nil
        FileUtils.touch(File.join(template_directory_option, described_class::DEFINITIONS_FILENAME))
      end

      it "returns a configured TemplateDirectoryRenderer" do
        renderer = instance_double(KubernetesTemplateRendering::TemplateDirectoryRenderer)
        expect(KubernetesTemplateRendering::TemplateDirectoryRenderer).to receive(:new)
                                               .with(
                                                 directories: [template_directory_option],
                                                 rendered_directory: render_directory,
                                                 color: nil,
                                                 region: nil,
                                                 cluster_type: nil,
                                                 variable_overrides: nil,
                                                 source_repo: nil
                                               )
                                               .and_return(renderer)

        expect(cli).to eq(renderer)
      end
    end

    context "and directory doesn't exist" do
      before do
        FileUtils.rm_rf(template_directory_option)
      end

      it "raises an exception" do
        expect{ cli }.to raise_exception(ArgumentError, /template directory not found/)
      end
    end
  end
end
