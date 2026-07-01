# frozen_string_literal: true

require "fileutils"
require "find"
require "tempfile"
require_relative "color"

module KubernetesTemplateRendering
  # Bounded, marker-based reconcile sweep replacing the destructive per-entry `rm -rf` prune.
  #
  # Lifecycle (driven by TemplateDirectoryRenderer):
  #   1. Construct (touches a marker file; its mtime is the cutoff) BEFORE any rendering/forking.
  #   2. Render writes files (mtime > marker); PlaceholderExpander copies preserve a just-rendered
  #      source mtime (also > marker).
  #   3. After all rendering, `sweep!` each scope root: delete files strictly older than the marker
  #      (leftovers from deleted/renamed entries), then remove now-empty directories.
  #
  # `spp/` subtrees are fenced out of the base sweep; per the ticket, deleted-SPP cleanup is a
  # manual `git rm`, never an automatic sweep.
  class Reconciler
    class OutOfScopeError < StandardError; end

    attr_reader :marker_mtime

    def initialize(rendered_directory)
      FileUtils.mkdir_p(rendered_directory)
      @marker = Tempfile.new(".reconcile-marker", rendered_directory)
      @marker.close
      @marker_mtime = File.mtime(@marker.path)
    end

    def sweep!(root:, fences: [])
      return unless File.directory?(root)

      real_root = File.realpath(root)
      fence_set = fences.select { |fence| File.exist?(fence) }.map { |fence| File.realpath(fence) }

      delete_stale_files(root, real_root, fence_set)
      remove_empty_dirs(root, fence_set)
    end

    def finish!
      @marker.unlink
    end

    private

    def delete_stale_files(root, real_root, fence_set)
      Find.find(root) do |path|
        if File.directory?(path)
          Find.prune if fenced?(path, fence_set)
          next
        end
        next unless File.file?(path)

        real_path = File.realpath(path)
        unless real_path == real_root || real_path.start_with?(real_root + File::SEPARATOR)
          raise OutOfScopeError, "reconcile: #{path} resolves outside sweep root #{root}"
        end

        if File.mtime(path) < @marker_mtime
          puts "Reconcile: removing stale file #{Color.magenta(path)}"
          File.delete(path)
        end
      end
    end

    def remove_empty_dirs(root, fence_set)
      Dir.glob(File.join(root, "**", "*/"))
         .reject { |dir| fenced?(dir, fence_set) }
         .sort
         .reverse # deepest paths first so parents empty out after their children
         .each do |dir|
        next unless File.directory?(dir)

        if Dir.empty?(dir)
          puts "Reconcile: removing empty directory #{Color.magenta(dir)}"
          Dir.rmdir(dir)
        end
      end
    end

    def fenced?(path, fence_set)
      return false if fence_set.empty?

      resolved = File.realpath(path)
      fence_set.any? { |fence| resolved == fence || resolved.start_with?(fence + File::SEPARATOR) }
    end
  end
end
