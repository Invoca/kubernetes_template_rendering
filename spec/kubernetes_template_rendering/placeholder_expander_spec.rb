# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

require_relative "../../lib/kubernetes_template_rendering/placeholder_expander"

RSpec.describe KubernetesTemplateRendering::PlaceholderExpander do
  let(:rendered_root) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(rendered_root)
  end

  describe ".expand!" do
    it "substitutes the placeholder token inside file contents" do
      source = File.join(rendered_root, "SPP-PLACEHOLDER")
      FileUtils.mkdir_p(source)
      File.write(File.join(source, "config.yaml"), "namespace: SPP-PLACEHOLDER\n")

      described_class.expand!(
        source_directory: source,
        target_name: "staging-qa02a",
        placeholder_token: "SPP-PLACEHOLDER"
      )

      dest_path = File.join(rendered_root, "staging-qa02a", "config.yaml")
      expect(File.read(dest_path)).to eq("namespace: staging-qa02a\n")
    end

    it "substitutes the placeholder token inside nested file paths" do
      source = File.join(rendered_root, "SPP-PLACEHOLDER")
      FileUtils.mkdir_p(File.join(source, "subdir-SPP-PLACEHOLDER"))
      File.write(File.join(source, "subdir-SPP-PLACEHOLDER", "x.yaml"), "data: ok\n")

      described_class.expand!(
        source_directory: source,
        target_name: "staging-qa02a",
        placeholder_token: "SPP-PLACEHOLDER"
      )

      dest = File.join(rendered_root, "staging-qa02a", "subdir-staging-qa02a", "x.yaml")
      expect(File.read(dest)).to eq("data: ok\n")
    end

    it "substitutes the suffix portion of the placeholder when it appears alone in contents" do
      source = File.join(rendered_root, "SPP-PLACEHOLDER")
      FileUtils.mkdir_p(source)
      File.write(File.join(source, "tags.yaml"), "tag: staging,PLACEHOLDER\n")

      described_class.expand!(
        source_directory: source,
        target_name: "staging-qa02a",
        placeholder_token: "SPP-PLACEHOLDER"
      )

      dest = File.join(rendered_root, "staging-qa02a", "tags.yaml")
      expect(File.read(dest)).to eq("tag: staging,qa02a\n")
    end

    it "preserves the source file's mtime on the destination" do
      source = File.join(rendered_root, "SPP-PLACEHOLDER")
      FileUtils.mkdir_p(source)
      source_file = File.join(source, "config.yaml")
      File.write(source_file, "data: ok\n")
      backdated = Time.now - 3600
      File.utime(backdated, backdated, source_file)

      described_class.expand!(
        source_directory: source,
        target_name: "staging-qa02a",
        placeholder_token: "SPP-PLACEHOLDER"
      )

      dest = File.join(rendered_root, "staging-qa02a", "config.yaml")
      expect(File.mtime(dest).to_i).to eq(backdated.to_i)
    end
  end

  describe "byte parity with legacy spp-transform.rb" do
    let(:fixture_root) { File.expand_path("../fixtures/placeholder_expander", __dir__) }
    let(:source_tree) { File.join(fixture_root, "source") }
    let(:expected_tree) { File.join(fixture_root, "expected_staging-qa02a") }
    let(:scratch_root) { Dir.mktmpdir }

    after { FileUtils.rm_rf(scratch_root) }

    it "produces byte-identical output to the legacy transform" do
      FileUtils.cp_r(File.join(source_tree, "SPP-PLACEHOLDER"), scratch_root)

      described_class.expand!(
        source_directory: File.join(scratch_root, "SPP-PLACEHOLDER"),
        target_name: "staging-qa02a",
        placeholder_token: "SPP-PLACEHOLDER"
      )

      expected_files = Dir.glob(File.join(expected_tree, "**", "*")).select { |p| File.file?(p) }
      expect(expected_files).not_to be_empty

      expected_files.each do |expected_path|
        relative = expected_path.sub("#{expected_tree}/", "")
        actual_path = File.join(scratch_root, relative)
        expect(File.exist?(actual_path)).to be(true), "missing #{relative}"
        expect(File.read(actual_path)).to eq(File.read(expected_path)), "content mismatch in #{relative}"
      end

      actual_files = Dir.glob(File.join(scratch_root, "staging-qa02a", "**", "*")).select { |p| File.file?(p) }
      expected_relatives = expected_files.map { |p| p.sub("#{expected_tree}/", "") }.sort
      actual_relatives = actual_files.map { |p| p.sub("#{scratch_root}/", "") }.sort
      expect(actual_relatives).to eq(expected_relatives)
    end
  end
end
