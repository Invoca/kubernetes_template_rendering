# frozen_string_literal: true

module TestHelpers
  def stub_puts(klass = nil)
    klass ||= described_class
    allow_any_instance_of(klass).to receive(:puts)
  end

  def build_definition(name:, rendered_directory:, template_directory:, variables:, deploy_groups: [], omitted_resources: [])
    {
      name => {
        "rendered_directory" => rendered_directory,
        "template_directory" => template_directory,
        "deploy_groups" => deploy_groups,
        "omitted_resources" => omitted_resources,
        "variables" => variables
      }
    }
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
