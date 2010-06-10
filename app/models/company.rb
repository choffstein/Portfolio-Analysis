require 'time'
require 'csv'

class Company < ActiveRecord::Base
  has_many :data_points, :autosave => true
  validates_presence_of :ticker, :name
  validates_uniqueness_of :ticker,  :case_sensitive => false

  def after_find
    update_data
  end

  def initialize(params = nil)
    super(params)

    self.name = Yahoo::YQL.get_company_name(self.ticker) if self.name.nil?
    self.sector = Yahoo::YQL.get_company_sector(self.ticker) if self.sector.nil?
    self.profile = Yahoo::YQL.get_company_profile(self.ticker) if self.profile.nil?

    self.save! #save before we load the data so we have a relevant id
    update_data
  end
    
  def update_data
    
    if self.data_points.size > 0
      sorted_data_points = self.data_points.sort{ |dp1, dp2|
            dp1.date <=> dp2.date
      }
      last_date = sorted_data_points[-1].date.time
    end

    # we look for 1 day ago because that is the market values available today
    today = 1.day.ago

    Rails.logger.info("#{last_date} vs #{today}")
    if last_date.nil?
      # THIS IS A HACK FOR TESTING PURPOSES ONLY!  CHANGE BACK TO today
      data = download_data(last_date, 2.days.ago)
      new_data_points = parse_data(data)
      self.data_points = new_data_points
    elsif last_date < today

      data = download_data(last_date, today)
      new_data_points = parse_data(data).sort { |dp1, dp2| 
            dp1.date <=> dp2.date 
      }
      # check to see if the adjusted closes match of our last date,
      # and the first date we download
      if sorted_data_points[-1].adjusted_close != new_data_points[0].adjusted_close
        # they don't match -- there must have been a split or a dividend.
        # we need to reload all the data
        Rails.logger.info("Looked like #{self.ticker} had a split/dividend ... reloading all the data")
        self.data_points.delete_all

        data = download_data(nil, today)
        new_data_points = parse_data(data)
        self.data_points = new_data_points
      else
        # we don't need to reload the data, so just load in the fresh stuff
        new_data_points[1...new_data_points.size].each { |ndp|
          self.data_points << ndp
        }
      end

      self.save! #save ourself...
    end
  end
    
  def data_point_dates
    self.data_points.map { |dp| dp.date }
  end
    
  def adjusted_close
    Hash[*self.data_points.map { |dp| [dp.date, dp.adjusted_close] }]
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

  private

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

    from_array =    from.nil? ? ['','',''] : array_for_date(from)
    to_array =      to.nil?   ? array_for_date(Time.now.getutc) : array_for_date(to)

    tries = MAX_DOWNLOAD_ATTEMPTS

    begin
      url = "/table.csv?s=#{ticker}&a=#{from_array[0]}&b=#{from_array[1]}&c=#{from_array[2]}&d=#{to_array[0]}&e=#{to_array[1]}&f=#{to_array[2]}&ignore=.csv"
      data = Net::HTTP.get 'ichart.finance.yahoo.com', url
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
    CSV.parse(data) { |row|

      dp = DataPoint.new( {:date => Utility::ParseDates::str_to_date(row[0]),
          :open => row[1].to_f,
          :high => row[2].to_f,
          :low  => row[3].to_f,
          :close => row[4].to_f,
          :volume => row[5].to_i,
          :adjusted_close => row[6].to_f,
          :company_id => self.id # need this for validation in DataPoint
        }) unless first
      dps << dp unless first
      first = false
    }

    return dps
  end
end