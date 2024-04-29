# frozen_string_literal: true

require_relative "../../lib/kubernetes_template_rendering/color"

RSpec.describe KubernetesTemplateRendering::Color do
  subject(:color) { described_class }

  it "outputs the expected ANSI color codes" do
    colors = {
      black: 30,
      red: 31,
      green: 32,
      brown: 33,
      blue: 34,
      magenta: 35
    }

    data = "output"

    colors.each do |name, code|
      expect(color.send(name, data)).to eq("\e[#{code}m#{data}\e[0m")
    end
  end
end
