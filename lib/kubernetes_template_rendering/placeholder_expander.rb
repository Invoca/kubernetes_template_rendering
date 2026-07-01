# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module KubernetesTemplateRendering
  # Expands a rendered placeholder-bearing output tree into a per-target sibling tree by
  # substituting the placeholder token in both file paths and file contents. Mirrors the
  # semantics of invocaops_docker/tools/spp-transform/spp-transform.rb.
  class PlaceholderExpander
    class << self
      def expand!(source_directory:, target_name:, placeholder_token:)
        placeholder_suffix = placeholder_token.rpartition('-').last
        target_suffix = target_name.rpartition('-').last

        source_root = Pathname.new(source_directory)
        dest_root = Pathname.new(source_directory.gsub(placeholder_token, target_name))

        Pathname.glob(source_root + "**" + "*").each do |source_path|
          next unless source_path.file?

          relative = source_path.relative_path_from(source_root).to_s
          relative_substituted = relative.gsub(placeholder_token, target_name)
          dest_path = dest_root + relative_substituted
          FileUtils.mkdir_p(dest_path.dirname)

          mtime = source_path.mtime
          contents = File.read(source_path)
          contents = contents.gsub(placeholder_token, target_name)
          contents = contents.gsub(placeholder_suffix, target_suffix)
          File.write(dest_path, contents)
          File.utime(mtime, mtime, dest_path)
        end
      end
    end
  end
end
