# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

require_relative "../../lib/kubernetes_template_rendering/reconciler"

RSpec.describe KubernetesTemplateRendering::Reconciler do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.rm_rf(root) }

  def write_with_mtime(path, mtime)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    File.utime(mtime, mtime, path)
  end

  before { stub_puts }

  describe ".validate_within_scope!" do
    it "is silent for a path inside the scope root" do
      expect { described_class.validate_within_scope!(File.join(root, "a/b"), root) }.to_not raise_error
    end

    it "raises for a relative path that escapes the scope root" do
      expect { described_class.validate_within_scope!(File.join(root, "../evil"), root) }
        .to raise_error(described_class::OutOfScopeError)
    end

    it "raises for an absolute path outside the scope root" do
      expect { described_class.validate_within_scope!("/somewhere/else", root) }
        .to raise_error(described_class::OutOfScopeError)
    end
  end

  describe "#sweep!" do
    let(:base) { File.join(root, "us-east-1/staging/orange") }
    let(:stale) { File.join(base, "deleted-entry/x.yaml") }
    let(:fresh) { File.join(base, "kept-entry/y.yaml") }
    let(:fenced) { File.join(base, "spp/qa02a/z.yaml") }

    it "deletes files older than the marker, keeps newer files, and fences excluded subtrees" do
      reconciler = described_class.new(root) # marker = now
      write_with_mtime(stale,  reconciler.marker_mtime - 60)
      write_with_mtime(fresh,  reconciler.marker_mtime + 60)
      write_with_mtime(fenced, reconciler.marker_mtime - 60) # old, but fenced -> survives

      reconciler.sweep!(root: base, fences: [File.join(base, "spp")])

      expect(File.exist?(fresh)).to be(true)
      expect(File.exist?(fenced)).to be(true)
      expect(File.exist?(stale)).to be(false)
      expect(File.directory?(File.dirname(stale))).to be(false) # emptied dir removed
    end

    it "is idempotent: a second sweep over the cleaned tree deletes nothing" do
      reconciler = described_class.new(root)
      write_with_mtime(fresh, reconciler.marker_mtime + 60)

      reconciler.sweep!(root: base)
      before_files = Dir.glob(File.join(base, "**", "*"))
      reconciler.sweep!(root: base)

      expect(Dir.glob(File.join(base, "**", "*"))).to eq(before_files)
      expect(File.exist?(fresh)).to be(true)
    end

    it "does nothing when the root does not exist" do
      reconciler = described_class.new(root)
      expect { reconciler.sweep!(root: File.join(root, "missing")) }.to_not raise_error
    end

    it "raises when a file resolves outside the sweep root via a symlink" do
      reconciler = described_class.new(root)
      outside = File.join(root, "outside.yaml")
      write_with_mtime(outside, reconciler.marker_mtime - 60)
      FileUtils.mkdir_p(base)
      File.symlink(outside, File.join(base, "escape.yaml"))

      expect { reconciler.sweep!(root: base) }.to raise_error(described_class::OutOfScopeError)
    end
  end
end
