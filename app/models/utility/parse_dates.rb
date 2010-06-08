# Author::    Corey M. Hoffstein  (corey@hoffstein.com)
# Copyright:: Copyright (c) 2010
# License::   Distributes under the same terms as Ruby

require 'third_base'

module Utility
  module ParseDates
    include ThirdBase

    def self.parsedate(str)
      d = Date.parse(str)
      return [d.year, d.month, d.day]
    end

    def self.is_valid?(str)
      (!str.nil? && str != "-" && str != "#N/A" && str != " " && str != "#DIV/0!")
    end

    # Month / Day / Year format
    def self.str_to_date(str)
      begin
        return Time.utc(*parsedate(str))
      rescue ArgumentError, TypeError
        raise "Invalid date: #{str}"
      end
    end
  end
end