require 'csv'
require 'date'
require 'time'

require 'net/http'
require 'uri'

require 'yaml'

class Company
  attr_reader :ticker, :name, :sector, :profile, :data_points
  
  def initialize(params = nil)
    params.each { |k, v|
      instance_variable_set("@#{k}",v)
    }
    @ticker = params[:ticker].upcase unless params[:ticker].nil?
   
    load_data
  end
    
  def load_data
    # try to re-download our info if we didn't get it last time...
    Status.info("Computing company info for #{@ticker}")

    file = "data/#{@ticker}.yml"
    if File.exists?(file)
      File.open(file, "r") { |f|
        info = YAML.load_file(file)
        @name = info[:name]
        @sector = info[:sector]
        @profile = info[:profile]
      }
    else
      @name = Yahoo::YQL.get_company_name(@ticker) if @name.nil? || @name == "N/A"
      @sector = Yahoo::YQL.get_company_sector(@ticker) if @sector.nil? || @sector == "N/A"
      @profile = Yahoo::YQL.get_company_profile(@ticker) if @profile.nil? || @profile == "N/A"

      File.open(file, "w") { |f|
        f.write YAML::dump({
                          :name => @name,
                          :sector => @sector,
                          :profile => @profile })
      }
    end

    data = download_data
    @data_points = parse_data(data)

    @data_point_hash = @data_points.each_with_object({}) { |dp, hsh|
      hsh[dp.date] = dp
    }
  end

  def values_at(dates)
    return dates.each_with_object(Hash.new) { |date, hsh|
      hsh[date] = @data_point_hash[date]
    }
  end
    
  def data_point_dates
    return @data_points.map { |dp| dp.date }
  end
    
  def adjusted_closes
    return @data_points.each_with_object({}) { |dp, hsh|
        hsh[dp.date] = dp.adjusted_close
    }
  end

  def log_returns
    # sort in ascending order
    sorted_data_points = DataPoint.find(:all, :order => "date ASC",
                                        :conditions => {:company_id => @id})

    log_returns = GSL::Vector.alloc(sorted_data_points.size-1)
    1.upto(sorted_data_points.size-1) { |i|
      log_returns[i-1] = Math.log(sorted_data_points[i].adjusted_close) -
                       Math.log(sorted_data_points[i-1].adjusted_close)
    }

    return log_returns
  end

  # The next three methods will try to update the current model if the
  # data hasn't already been saved
  def get_name
    if @name.nil?
      @name = Yahoo::YQL.get_company_name(ticker)
    end
    return @name
  end

  def get_profile
    if @profile.nil?
      @profile = Yahoo::YQL.get_company_profile(ticker)
    end
    return @profile
  end

  def get_sector
    if @sector.nil?
      @sector = Yahoo::YQL.get_company_sector(ticker)
    end
    return @sector
  end

  def dividends
    quarters = { 1 => "jan",
                 2 => "apr",
                 3 => "jul",
                 4 => "oct" }

    Status.info("Downloading dividend information for #{@ticker}")
    data = Net::HTTP.get URI.parse("http://ichart.finance.yahoo.com/table.csv?s=#{@ticker}&g=v&ignore=.csv")

    Status.info("Parsing dividend information for #{@ticker}")

    dividends = {}
    i = 0
    first = true
    current_quarter = nil
    dividends_per_year = Hash.new(0.0)
    CSV.parse(data) { |row|
      if !first
        date = Utility::ParseDates::str_to_date(row[0])
        dividend = row[1].to_f

        1.upto(4) { |i|
          # check if we need to roll-over
          year = i == 4 ? date.year + 1 : date.year
          next_quarter = i == 4 ? 1 : i+1

          # is our current date less than the beginning of the next quarter /
          # this quarter end?
          quarter_begin = Time.utc(date.year, quarters[i], 1, 12, 0, 0)
          quarter_end = Time.utc(year, quarters[next_quarter], 1, 12, 0, 0)
          if quarter_begin < date && date <= quarter_end
            current_quarter = i
          end
        }

        key = "#{date.year}Q#{current_quarter}"
        
        if dividends[key].nil?
          dividends[key] =  dividend
          dividends_per_year[date.year] += 1
        else
          #they put two dividends in the same quarter
          # is it a special dividend or should we just bump a quarter

          # it should be an unusually high dividend INCREASE to count as a
          # special dividend
          if (Math.log(dividend) - 
                    Math.log(dividends[key])).abs > 1.609 #~500% hike

            #we'll take the one that was closest to the previous
            # remember, we are 'walking backwards' (because of how we read the
            # data, so use the 'last' quarter (which is technically the future)
            if current_quarter == 4
              previous_key = "#{date.year+1}Q1"
            else
              previous_key = "#{date.year}Q#{current_quarter+1}"
            end

            # wierd corner case -- this was our second dividend
            # just take the smaller one
            if dividends[previous_key].nil?
              dividends[key] = [dividends[key], dividend].min
            else
              # choose the entry that is closest to the previous quarterly
              # payment.  would probably be better if we used a 'best fit growth'
              # line to estimate which payments are outliers, but this works
              distance_one = (Math.log(dividends[previous_key])-dividends[key]).abs
              distance_two = (Math.log(dividends[previous_key])-dividend).abs

              if distance_two < distance_one
                dividends[key] = dividend
              end
            end
          else
            # these are probably monthly dividends
            # add it to the current quarter
            dividends[key] +=  dividend
            dividends_per_year[date.year] += 1
          end
        end
      end
      first = false
    }

    # if dividends are annual or semi-annual, split them up to make them
    # quarterly
    dividends_per_year.each { |k,v|
      if v < 4 && k != Date.today.year #make sure it isn't the current year...
        q1 = dividends["#{k}Q1"].nil? ? 0.0 : dividends["#{k}Q1"]
        q2 = dividends["#{k}Q2"].nil? ? 0.0 : dividends["#{k}Q2"]
        q3 = dividends["#{k}Q3"].nil? ? 0.0 : dividends["#{k}Q3"]
        q4 = dividends["#{k}Q4"].nil? ? 0.0 : dividends["#{k}Q4"]
        total = q1 + q2 + q3 + q4

        dividends["#{k}Q1"] = total/4.0
        dividends["#{k}Q2"] = total/4.0
        dividends["#{k}Q3"] = total/4.0
        dividends["#{k}Q4"] = total/4.0
      end
    }

    return dividends
  end

  private

  MAX_DOWNLOAD_ATTEMPTS = 10
  
  def download_data
    data = nil
    today = Date.today
    file = "data/#{@ticker}_#{today.day}_#{today.mon}_#{today.year}.csv"
    
    if File.exist?(file)
      File.open(file, "r") { |f|
        data = f.read
      }
    else
      #FIX: Not a system call?
      system("rm data/#{@ticker}*")

      tries = MAX_DOWNLOAD_ATTEMPTS

      Status.info("Downloading data for #{@ticker}")
      begin
        data = Net::HTTP.get URI.parse("http://ichart.finance.yahoo.com/table.csv?s=#{ticker}&ignore=.csv")
        File.open(file, "w") { |f|
          f.write data
        }
      rescue Timeout::Error
        if tries > 0
          tries = tries - 1
          sleep(MAX_DOWNLOAD_ATTEMPTS - tries)
          retry
        else
          raise "Could not download data..."
        end
      end
    end
    return data
  end

  def parse_data(data)
    dps = []
    first = true
    Status.info("Parsing time-series data for #{@ticker}")
    begin
      CSV.parse(data) { |row|
          dp = DataPoint.new({
              :date => Utility::ParseDates::str_to_date(row[0]).to_i,
              :open => row[1].to_f,
              :high => row[2].to_f,
              :low  => row[3].to_f,
              :close => row[4].to_f,
              :volume => row[5].to_i,
              :adjusted_close => row[6].to_f
            }) unless first
          dps << dp unless first
          first = false
        }
      
      # delete the file after use
      #File.delete("tmp/#{@ticker}.csv") if File.exist?("tmp/#{@ticker}.csv")
    rescue
      raise "Unable to load data for #{@ticker}"
    end
    return dps
  end
end