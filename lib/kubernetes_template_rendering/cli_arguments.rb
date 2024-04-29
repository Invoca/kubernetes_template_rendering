# frozen_string_literal: true

module KubernetesTemplateRendering
  CLIArguments =
    Struct.new(
      :rendered_directory,
      :template_directory,
      :fork,
      :makeflags,
      :jsonnet_library_path,
      :cluster_type,
      :region,
      :color,
      :variable_overrides
    ) do
      def valid?
        rendered_directory && template_directory
      end

      def fork?
        if fork.nil?
          makeflags&.include?('-j')
        else
          fork
        end
      end

      def render_files?
        true
      end
    end
end
