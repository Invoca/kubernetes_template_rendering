# frozen_string_literal: true

require_relative "lib/kubernetes_template_rendering/version"

Gem::Specification.new do |spec|
  spec.name    = "kubernetes_template_rendering"
  spec.version = KubernetesTemplateRendering::VERSION
  spec.authors = ["Octothorpe"]
  spec.email = ["octothorpe@invoca.com"]

  spec.summary     = "Tool for rendering ERB and Jsonnet templates"
  spec.description = spec.summary
  spec.homepage    = "https://github.com/Invoca/kubernetes_template_rendering"

  spec.metadata = {
    "allowed_push_host" => "TODO: Set to your gem server 'https://example.com'",
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/Invoca/kubernetes_template_rendering",
    "changelog_uri"     => "https://github.com/Invoca/kubernetes_template_rendering/blob/main/CHANGELOG.md",
  }

  spec.required_ruby_version = ">= 3.1.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?('bin/', 'test/', 'spec/', 'features/', '.git', 'appveyor', 'Gemfile')
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport"
  spec.add_dependency "jsonnet"
  spec.add_dependency "invoca-utils"
end
