# frozen_string_literal: true

RSpec.describe Invoca::KubernetesTemplates do
  it "has a version number" do
    expect(Invoca::KubernetesTemplates::VERSION).not_to be nil
  end
end
