# frozen_string_literal: true

require_relative "template_directory_renderer"
require_relative "cli_arguments"

module KubernetesTemplateRendering
  class CLI
    DEFINITIONS_FILENAME = "definitions.yaml"

    Arguments = CLIArguments

    class << self
      def parse_and_render(options)
        renderer, args = parse(options)

        renderer.render(args)
      end

      private

      def parse(options)
        args = Arguments.new

        parser = OptionParser.new do |op|
          op.banner = "Usage: #{$PROGRAM_NAME} --rendered-directory=<directory> <template directory>"

          op.on("--rendered-directory=RENDERED_DIRECTORY",     "set the directory where rendered output is written")                  { args.rendered_directory = _1 }
          op.on("--[no-]fork",                                 "disable/enable fork")                                                 { |fork| args.fork = fork }
          op.on("--makeflags=MAKEFLAGS",                       "pass through makeflags so that we can infer fork preference from -j") { args.makeflags = _1 }
          op.on("--jsonnet_library_path=JSONNET_LIBRARY_PATH", "set the jsonnet library path")                                        { args.jsonnet_library_path = _1 }
          op.on("--cluster_type=CLUSTER_TYPE",                 "set the specific cluster type to render")                             { args.cluster_type = _1 }
          op.on("--region=REGION",                             "set the specific region to render")                                   { args.region = _1 }
          op.on("--color=COLOR",                               "set the specific color to render")                                    { args.color = _1 }

          op.on("--variable-override=KEY:VALUE", "override a variable value set within definitions.yaml") do |override|
            args.variable_overrides ||= {}
            args.variable_overrides.merge!(Hash[[override.split(":", 2)]])
          end

          op.on("-h", "--help") do
            puts op
            exit
          end
        end

        parser.parse!(options)
        args.template_directory = options.first

        unless args.valid?
          STDERR.puts(parser)
          exit(1)
        end

        [renderer_from_args(args), args]
      end

      def renderer_from_args(args)
        directories = template_directories(args.template_directory, DEFINITIONS_FILENAME)

        TemplateDirectoryRenderer.new(
          directories: directories,
          rendered_directory: args.rendered_directory,
          cluster_type: args.cluster_type,
          region: args.region,
          color: args.color,
          variable_overrides: args.variable_overrides
        )
      end

      def template_directories(template_directory, definitions_file)
        File.directory?(template_directory) or raise ArgumentError, "template directory not found--make sure to include templates/ prefix: #{template_directory}"
        directories = Dir["#{template_directory}/**/#{definitions_file}"]
        directories.map { |directory| File.dirname(directory) }
      end
    end
  end
end
