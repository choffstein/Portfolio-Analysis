module Utility
  module Options
    def self.set_default_options(options, default_options)
      default_options.map { |pair|
        options.store(*pair) unless options.include?(pair[0])
      }
      return options
    end
  end
end