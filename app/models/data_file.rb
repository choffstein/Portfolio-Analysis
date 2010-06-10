require 'csv'

class DataFile

  def initialize(upload)
    @file_name  = upload[:datafile].original_filename
    @data = {}

    headers = []
    type = []

    row_number = 0
    CSV.parse(upload[:datafile].read) { |row|
      if row_number == 0

        # Set up the headers for each column
        headers = row
        row.each { |e|
          @data[e.downcase] = []
        }

      elsif row_number == 1
        # Set up each columns type
        types = row.map { |e| e.downcase.to_sym }
      else
        # Convert the column entries
        0.upto(row.size-1) { |i|
          @data[headers[i]] << CONVERTERS[types[i]].call(row[i])
        }
      end
      row_number = row_number + 1
    }
  end

  def method_missing(method, *args, &block)
    if args.size == 0 & block.nil?
      return @data[method.to_s] #try to return the data
    else
      raise
    end
  end

  private
  CONVERTERS = {  :date => lambda { |s| Utility::ParseDates.str_to_date(s) },
                  :float => lambda { |f| f.to_f },
                  :string => lambda { |s| s.to_s },
                  :integer => lambda { |i| i.to_i }
  }
end
