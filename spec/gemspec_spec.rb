# frozen_string_literal: true

require "bundler"

RSpec.describe "gem specification" do
  let(:specification) do
    Gem::Specification.load(File.expand_path("../kubernetes_template_rendering.gemspec", __dir__))
  end
  let(:activesupport_requirement) do
    specification.runtime_dependencies.find { |dependency| dependency.name == "activesupport" }.requirement
  end

  %w[5.0.0 6.1.7.10 7.1.6 7.2.3.1 7.2.4].each do |version|
    it "keeps ActiveSupport #{version} eligible for existing consumers" do
      expect(activesupport_requirement.satisfied_by?(Gem::Version.new(version))).to be true
    end
  end

  %w[8.0.5.2 8.0.5.3 8.0.6 8.1.4.1 8.1.4.2 8.1.5].each do |version|
    it "allows patched ActiveSupport #{version}" do
      expect(activesupport_requirement.satisfied_by?(Gem::Version.new(version))).to be true
    end
  end

  %w[9.0.0 9.0.1 10.0.0].each do |version|
    it "does not claim compatibility with ActiveSupport #{version}" do
      expect(activesupport_requirement.satisfied_by?(Gem::Version.new(version))).to be false
    end
  end

  it "keeps Ruby 3.1 eligible for consumers using older ActiveSupport" do
    expect(specification.required_ruby_version.satisfied_by?(Gem::Version.new("3.1.0"))).to be true
  end
end

RSpec.describe "ActiveSupport CI matrix" do
  {
    "7_2" => { allowed: %w[7.2.3.1], excluded: %w[7.2.3 7.2.3.2 8.0.5.2] },
    "8_0" => { allowed: %w[8.0.5.2 8.0.5.3 8.0.6], excluded: %w[7.2.3.1 8.0.5.1 8.1.4.1] },
    "8_1" => { allowed: %w[8.1.4.1 8.1.4.2 8.1.5], excluded: %w[8.0.5.2 8.1.4 8.2.0] }
  }.each do |branch, versions|
    context "with the #{branch} Gemfile" do
      let(:requirement) do
        dsl = Bundler::Dsl.new
        dsl.eval_gemfile(File.expand_path("../gemfiles/activesupport_#{branch}.gemfile", __dir__))
        dsl.dependencies.find { |dependency| dependency.name == "activesupport" }.requirement
      end

      versions[:allowed].each do |version|
        it "exercises ActiveSupport #{version}" do
          expect(requirement.satisfied_by?(Gem::Version.new(version))).to be true
        end
      end

      versions[:excluded].each do |version|
        it "excludes ActiveSupport #{version} from this branch" do
          expect(requirement.satisfied_by?(Gem::Version.new(version))).to be false
        end
      end
    end
  end
end
