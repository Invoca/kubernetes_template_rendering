# frozen_string_literal: true

module Invoca
  module KubernetesTemplates
    module Color
      class << self
        def black(str)
          "\e[30m#{str}\e[0m"
        end

        def red(str)
          "\e[31m#{str}\e[0m"
        end

        def green(str)
          "\e[32m#{str}\e[0m"
        end

        def brown(str)
          "\e[33m#{str}\e[0m"
        end

        def blue(str)
          "\e[34m#{str}\e[0m"
        end

        def magenta(str)
          "\e[35m#{str}\e[0m"
        end
      end
    end
  end
end
