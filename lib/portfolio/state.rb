module Portfolio
  # This class encompasses the current state of the portfolio
  class State
    attr_reader :tickers
    attr_reader :time_series
    attr_reader :dates
    attr_reader :log_returns
    attr_reader :covariance_matrix
    attr_reader :correlation_matrix
    attr_reader :number_of_shares
        
    def initialize(params = {})
      @number_of_shares = params[:number_of_shares]
      @tickers = params[:tickers]
            
      # check if the time series already exists
      if params[:time_series].nil?
        # find the shared dates between all tickers in the portfolio
        first = true
        companies = {}
        keys = []
        @tickers.each { |ticker|
          c = Company.first(:conditions => {:ticker => ticker})
          if c.nil?
            #if we can't find the company, create a new one (and download the data)
            c = Company.new(ticker)
            c.save!
          end
          companies[ticker] = c
                
          if first
            keys = c.data_point_dates
            first = false
          else
            keys = keys & c.data_point_dates
          end
        }
            
        @dates = keys.sort
            
        # compute the time series
        @time_series = {}
        0.upto(holdings.size-1) { |i|
          @time_series[ticker] = companies[ticker].adjusted_close_series.select{ |k,v| @dates.include?(k) }
        }
      else
        # the time series already exists, so just copy it
        @time_series = params[:time_series]
        @dates = params[:dates]
      end
               
      # compute or copy the log returns, covariance matrix, and correlation matrix
      @log_returns        = params[:log_returns].nil? ? compute_log_returns(@dates) : params[:log_returns]
      @covariance_matrix  = params[:covariance_matrix].nil? ? compute_covariance_matrix(@log_returns) : params[:covariance_matrix]
      @correlation_matrix = params[:correlation_matrix].nil? ? compute_correlation_matrix(@covariance_matrix) : params[:correlation_matrix]
    end
        
    # Returns the covariance of the log-returns for a given time slice
    # [offset, offset+window] (inclusive)
    def compute_covariance_by_window(offset, window=nil)
      window ||= @dates.size - offset
            
      raise "offset must be greater than or equal to zero" unless offset > 0
      raise "window size must be greater than zero" unless window > 0
      raise "offset + window must be less than total number of dates" unless offset+window < @dates.size
            
      covariance_matrix = GSL::Matrix(@tickers.size, @tickers.size)
      0.upto(@holdings.size-1) { |i|
        i.upto(@holdings.size-1) { |j|
          cov = GSL::Stats::covariance(@log_returns.row(i).get(offset...offset+window),
            @log_returns.row(j).get(offset...offset+window))
          covariance_matrix[i,j] = cov
          covaraince_matrix[j,i] = cov
        }
      }
      return covariance_matrix
    end
        
    # dates is an array of dates
    def select_dates(dates)
      dates = @dates.values_at(*dates)
      lr = compute_log_returns(dates)
      cov = compute_covariance_matrix(lr)
      corr = compute_correlation_matrix(corr)
            
      params = {  :download => false,
        :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :log_returns => lr,
        :covariance_matrix => cov,
        :correlation_matrix => corr,
        :time_series => @time_series.values.map { |holding| holding.select { |k,v| dates.include?(k) } }
      }
            
      return State.new(params)
    end
        
    #computes a slice by time index
    def slice(offset, window=nil)
      window ||= @dates.size - offset
      raise "offset must be greater than or equal to zero" unless offset > 0
      raise "window size must be greater than zero" unless window > 0
      raise "offset + window must be less than total number of dates" unless offset+window < @dates.size
            
      lr = @log_returns.submatrix(0, offset, @holdings.size-1, window)
      cov = compute_covariance_matrix(lr)
      corr = compute_correlation_matrix(corr)
      dates = @dates[offset...offset+window]
            
      params = {  :download => false,
        :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :log_returns => lr,
        :covariance_matrix => cov,
        :correlation_matrix => corr,
        :time_series => @time_series.map { |holding| holding.values.select { |k,v| dates.include?(k) } }
      }
                   
      return State.new(params)
    end
        
    # compute the current weights of the portfolio
    def current_weights
      weights = GSL::Vector.alloc(@tickers.size)
      0.upto(@tickers.size-1) { |i|
        weights[i] = @number_of_shares[i] * @time_series[@tickers[i]][@dates[-1]]
      }
            
      return (weights / weights.sum)
    end
        
    #compute the portfolio log return vector
    def to_return_vector
      daily_portfolio_value = GSL::Vector.alloc(@dates.size)
            
      0.upto(@dates.size-1) { |d|
        daily_portfolio_value[d] = 0
                
        0.upto(@tickers.size-1) { |i|
          daily_portfolio_value[d] += @weights[i] * @time_series[@tickers[i]][@dates[d]]
        }
      }
      daily_portfolio_value = Math.log(daily_portfolio_value)
            
      # the log differences
      return (daily_portfolio_value[1...@dates.size] - daily_portfolio_value[0...@dates.size-1])
    end

    private
    def comptue_log_returns(dates)
      log_returns = GSL::Matrix(@tickers.size, @dates.size-1)
      0.upto(@holdings.size-1) { |i|
        1.upto(dates.size-1) { |d|
          log_returns[i,d] = Math.log(@time_series[ticker][dates[d]]) -
            Math.log(@time_series[ticker][dates[d-1]])
        }
      }
      return log_returns
    end
        
    # Assumes @log_returns is filled
    def compute_covariance_matrix(log_returns)
      covariance_matrix = GSL::Matrix(@tickers.size, @tickers.size)
      0.upto(@holdings.size-1) { |i|
        i.upto(@holdings.size-1) { |j|
          cov = GSL::Stats::covariance(log_returns.row(i), log_returns.row(j))
          covariance_matrix[i,j] = cov
          covaraince_matrix[j,i] = cov #symmetric matrix
        }
      }
      return covariance_matrix
    end
        
    # Assumes @covariance_matrix is filled
    def compute_correlation_matrix(covariance_matrix)
      correlation_matrix = GSL::Matrix(@tickers.size, @tickers.size)
      0.upto(@holdings.size-1) { |i|
        i.upto(@holdings.size-1) { |j|
          corr = covariance_matrix[i,j] / Math.sqrt(covariance_matrix[i,i] * covariance_matrix[j,j])
          correlation_matrix[i,j] = corr
          correlation_matrix[j,i] = corr #symmetric matrix
        }
      }
      return correlation_matrix
    end
  end
end