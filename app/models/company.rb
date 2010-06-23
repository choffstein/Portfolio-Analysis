require 'csv'
require 'date'
require 'time'

require 'net/http'
require 'uri'

class Company < ActiveRecord::Base
  has_many :data_points, :autosave => true
  validates_presence_of :ticker, :name
  validates_uniqueness_of :ticker,  :case_sensitive => false

  def after_find
    update_data
  end

  def initialize(params = nil)
    params[:ticker] = params[:ticker].downcase unless params[:ticker].nil?
    super(params)
    
    self.name = Yahoo::YQL.get_company_name(self.ticker) if self.name.nil?
    self.sector = Yahoo::YQL.get_company_sector(self.ticker) if self.sector.nil?
    self.profile = Yahoo::YQL.get_company_profile(self.ticker) if self.profile.nil?

    self.save! #save before we load the data so we have a relevant id
    update_data
  end
    
  def update_data
    if self.last_update.nil? || self.last_update < Date.today

      # try to re-download our info if we didn't get it last time...
      Status.info("Computing company info for #{self.ticker}")
      self.name = Yahoo::YQL.get_company_name(self.ticker) if self.name.nil? || self.name == "N/A"
      self.sector = Yahoo::YQL.get_company_sector(self.ticker) if self.sector.nil? || self.sector == "N/A"
      self.profile = Yahoo::YQL.get_company_profile(self.ticker) if self.profile.nil? || self.profile == "N/A"

      if self.data_points.size > 0
        sorted_data_points = DataPoint.find(:all, :order => "date ASC",
                                          :conditions => {:company_id => self.id})
        last_date = sorted_data_points[-1].date
      end

      # Get the last week-day (for market prices)
      # Monday (0) needs Friday (3 days ago)
      # Sunday (7) needs Friday (2 days ago)
      # All else need the previous day (1 day ago)
      today = Date.today.wday
      if today == 0
        today = 3.days.ago
      elsif today == 7
        today = 2.days.ago
      else
        today = 1.day.ago
      end

      if last_date.nil?
        data = download_data(last_date, today)
        new_data_points = parse_data(data)

        #use crewait to perform bulk insert
        Status.info("Loading data-points into database")
        Crewait.start_waiting
        new_data_points.each { |p| DataPoint.crewait(p) }
        Crewait.go!

      elsif last_date < today.to_i

        data = download_data(last_date, today)
        new_data_points = parse_data(data).sort { |dp1, dp2|
              dp1[:date] <=> dp2[:date]
        }

        #Rails.logger.info(sorted_data_points[-1])
        #Rails.logger.info(new_data_points[0])

        # check to see if the adjusted closes match of our last date,
        # and the first date we download
        if sorted_data_points[-1].adjusted_close != new_data_points[0][:adjusted_close]
          # they don't match -- there must have been a split or a dividend.
          # we need to reload all the data
          Status.info("Looks like #{self.ticker} had a split/dividend ... reloading all the data")
          self.data_points.delete_all

          data = download_data(nil, today)
          new_data_points = parse_data(data)
          
          # use ar-extensions to do bulk import
          Status.info("Loading data-points into database")
          Crewait.start_waiting
          new_data_points.each { |p| DataPoint.crewait(p) }
          Crewait.go!
        else
          # we don't need to reload the data, so just load in the fresh stuff
          Status.info("Loading data-points into database")
          Crewait.start_waiting
          new_data_points[1...new_data_points.size].map { |ndp|
            DataPoint.crewait(ndp)
          }
          Crewait.go!
        end
      end

      #reload our data-points
      self.data_points = DataPoint.all(:conditions => {:company_id => self.id})

      generate_image
      self.last_update = Date.today
      
      self.save!
    end

    @data_point_hash = self.data_points.each_with_object({}) { |dp, hsh|
      hsh[dp.date] = dp
    }
  end

  def values_at(dates)
    return dates.each_with_object(Hash.new) { |date, hsh|
      hsh[date] = @data_point_hash[date]
    }
  end
    
  def data_point_dates
    return self.data_points.map { |dp| dp.date }
  end
    
  def adjusted_closes
    return self.data_points.each_with_object({}) { |dp, hsh|
        hsh[dp.date] = dp.adjusted_close
    }
  end

  def log_returns
    # sort in ascending order
    sorted_data_points = DataPoint.find(:all, :order => "date ASC",
                                        :conditions => {:company_id => self.id})

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
    if self.name.nil?
      self.name = Yahoo::YQL.get_company_name(ticker)
    end
    return self.name
  end

  def get_profile
    if self.profile.nil?
      self.profile = Yahoo::YQL.get_company_profile(ticker)
    end
    return self.profile
  end

  def get_sector
    if self.sector.nil?
      self.sector = Yahoo::YQL.get_company_sector(ticker)
    end
    return self.sector
  end

  def dividends
    quarters = { 1 => "jan",
                 2 => "apr",
                 3 => "jul",
                 4 => "oct" }

    Status.info("Downloading dividend information for #{self.ticker}")
    data = Net::HTTP.get URI.parse("http://ichart.finance.yahoo.com/table.csv?s=#{self.ticker}&g=v&ignore=.csv")

    Status.info("Parsing dividend information for #{self.ticker}")
    dividends = {}

    i = 0
    first = true
    current_quarter = nil
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
              distance_one = (Math.log(dividends[previous_key])-dividends[key]).abs
              distance_two = (Math.log(dividends[previous_key])-dividend).abs

              if distance_two < distance_one
                dividends[key] = dividend
              end
            end
          else
            # these are probably monthly dividends -- add it to the quarterly
            dividends[key] +=  dividend
          end
        end
      end
      first = false
    }

    return dividends
  end

  private

  def generate_image
    if self.image_generation_time.nil? || 
          self.image_generation_time < Date.today ||
          !File.exist?("public/images/tickers/#{self.ticker}.png")

      Status.info("Generated graph of adjusted closes for #{self.ticker}")
      adjusted_close = adjusted_closes.sort[(-[adjusted_closes.size,1000].min)..-1] #take last 5 years

      lc = GoogleChart::LineChart.new
      lc.width = 600
      lc.height = 300
      lc.title = "Adjusted Close"

      dates = adjusted_close.map { |d,v| d }
      values = adjusted_close.map { |d,v| v}

      lc.data "Adjusted Close", values, 'FF6600'

      lc.encoding = :extended
      lc.show_legend = true

      lc.axis :left, :range => [(values.min*0.9).floor, (values.max*1.1).ceil],
        :color => '000000', :font_size => 10, :alignment => :center

      # FIX: Make this global?  Local?  Class method of array?
      def every(a, n)
        a.select {|x| a.index(x) % n == 0}
      end
      

      labels = every(dates.map{ |t| Time.at(t).strftime("%m/%d/%Y")}, 100)
      labels << Time.at(dates[-1]).strftime("%m/%d/%Y")

      lc.axis :bottom, :range => [1, dates.size],
        :color => '000000', :font_size => 8, :alignment => :center,
        :labels => labels

      extras = {
        :chg => "10,10,1,5"
      }
      lc.write_to("public/images/tickers/#{self.ticker}", extras)

      self.image_generation_time = Date.today
    end
  end

  MAX_DOWNLOAD_ATTEMPTS = 10
  
  def download_data(from=nil, to=nil)

    # inner helper function
    def array_for_date(d)
      day = "#{d.day}"
      month = ""
      if d.mon < 11
        month = "0#{d.mon-1}"
      else
        month = "#{d.mon}"
      end
      year = "#{d.year}"

      return [month, day, year]
    end

    from_array =    from.nil? ? ['','',''] : array_for_date(Time.at(from))
    to_array =      to.nil?   ? array_for_date(Time.now.getutc) : array_for_date(to)

    tries = MAX_DOWNLOAD_ATTEMPTS

    Status.info("Downloading data for #{self.ticker}")
    begin
      data = Net::HTTP.get URI.parse("http://ichart.finance.yahoo.com/table.csv?s=#{ticker}&a=#{from_array[0]}&b=#{from_array[1]}&c=#{from_array[2]}&d=#{to_array[0]}&e=#{to_array[1]}&f=#{to_array[2]}&ignore=.csv")
    rescue Timeout::Error
      if tries > 0
        tries = tries - 1
        sleep(MAX_DOWNLOAD_ATTEMPTS - tries)
        retry
      else
        raise
      end
    end

    return data
  end

  def parse_data(data)
    dps = []
    first = true
    Status.info("Parsing time-series data for #{self.ticker}")
    begin
      CSV.parse(data) { |row|
          dp = {
              :date => Utility::ParseDates::str_to_date(row[0]).to_i,
              :open => row[1].to_f,
              :high => row[2].to_f,
              :low  => row[3].to_f,
              :close => row[4].to_f,
              :volume => row[5].to_i,
              :adjusted_close => row[6].to_f,
              :company_id => self.id
            } unless first
          dps << dp unless first
          first = false
        }
      
      # delete the file after use
      File.delete("tmp/#{self.ticker}.csv") if File.exist?("tmp/#{self.ticker}.csv")
    rescue
      raise "Unable to load data for #{@ticker}"
    end
    return dps
  end
end