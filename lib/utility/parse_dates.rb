# Author::    Corey M. Hoffstein  (corey@hoffstein.com)
# Copyright:: Copyright (c) 2010
# License::   Distributes under the same terms as Ruby

require 'third_base'

module Utility
  module ParseDates
    include ThirdBase

    # Month / Day / Year format
    def self.str_to_date(str)
      begin
        year, month, day = str.split('-').map { |e| e.to_i }
        #FIX: Use 12PM here to get around the 4 hour time difference hack
        return Time.utc(year, month, day, 12)
      rescue ArgumentError, TypeError
        raise "Invalid date: #{str}"
      end
    end
  end
end