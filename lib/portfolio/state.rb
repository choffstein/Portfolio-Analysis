module Portfolio
  # This class encompasses the current state of the portfolio
  # over a given time-frame.
  class State
    attr_reader :tickers
    attr_reader :time_series
    attr_reader :dates
    attr_reader :log_returns
    attr_reader :covariance_matrix
    attr_reader :correlation_matrix
    attr_reader :weights
    attr_reader :number_of_shares
        
    def initialize(params = {})
      Status.info("Initializing portfolio state")
      @number_of_shares = params[:number_of_shares]
      @tickers = params[:tickers].map { |ticker| ticker.downcase}
            
      # check if the time series already exists
      if params[:time_series].nil?
        # find the shared dates between all tickers in the portfolio
        first = true
        @companies = {}
        keys = []
        Status.update("Loading company data")
        @tickers.each { |ticker|
          c = Company.first(:conditions => {:ticker => ticker})
          if c.nil?
            #if we can't find the company, create a new one (and download the data)
            c = Company.new({:ticker => ticker})
            c.save!
          end
          @companies[ticker] = c
                
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
        @tickers.each { |ticker|
          selected_values = @companies[ticker].values_at(@dates)
          @time_series[ticker] = selected_values.each_with_object({}) { |(k,v), hsh|
            hsh[k] = v.adjusted_close
          }
        }
      else
        # the time series already exists, so just copy it
        @time_series = params[:time_series]
        @dates = params[:dates]
      end
               
      # compute or copy the log returns, covariance matrix, and correlation matrix
      if !params[:log_returns].nil?
        @log_returns = params[:log_returns]
      else
        compute_log_returns
      end

      if !params[:covariance_matrix].nil?
        @covariance_matrix  = params[:covariance_matrix]
      else
        compute_covariance_matrix
      end

      if !params[:correlation_matrix].nil?
        @correlation_matrix = params[:correlation_matrix]
      else
        compute_correlation_matrix
      end

      @weights = compute_weights
    end
        
    # dates is an array of dates
    def select_dates(dates)
      Status.info("Computing portfolio time-slice")
      
      dates = @dates.values_at(*dates)
      select_time_series = @tickers.each_with_object({}) { |ticker, hsh|
        hsh[ticker] = dates.each_with_object({}) { |date, hsh|
          hsh[date] = @time_series[ticker][date]
        }
      }
      
      params = {  :download => false,
        :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :time_series => select_time_series
      }
            
      return State.new(params)
    end
        
    #computes a slice by time index
    def slice(offset, window=nil)
      window ||= @dates.size - offset
      
      raise "offset must be greater than or equal to zero" unless offset > 0
      raise "window size must be greater than zero" unless window > 0
      raise "offset + window must be less than total number of dates" unless offset+window <= @dates.size

      Status.info("Computing portfolio time-slice")
      dates = @dates[offset...offset+window]

      select_time_series = @tickers.each_with_object({}) { |ticker, hsh|
        hsh[ticker] = dates.each_with_object({}) { |date, hsh|
          hsh[date] = @time_series[ticker][date]
        }
      }
            
      params = {  :download => false,
        :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :time_series => select_time_series
      }
                   
      return State.new(params)
    end
        
    #compute the portfolio log return vector
    def to_log_return_vector
      Status.info("Creating portfolio log returns")
      #shouldn't really need this...
      compute_log_returns unless !@log_returns.nil?
      compute_weights unless !@weights.nil?
      
      begin
        # using @log_returns,
        @portfolio_log_returns = GSL::Vector.alloc(@dates.size)
        @portfolio_log_returns.set_all(0.0)
        0.upto(@log_returns.size2 - 1) { |d|

          # add each share's value to the overall portfolio value
          0.upto(@tickers.size-1) { |i|
           @portfolio_log_returns[d] += @weights[i] * @log_returns[i,d]
          }
        }
      end unless !@portfolio_log_returns.nil?
      
      return @portfolio_log_returns
    end

    # perform a monte-carlo 
    def monte_carlo(periods_forward = 100, n = 1000, block_size = 5)
      log_returns = self.to_log_return_vector
      results = Statistics::Bootstrap::block_bootstrap(log_returns, periods_forward, block_size, n)
      series = results[:series]

      current_portfolio_value = compute_current_portfolio_value

      # given our current portfolio value and a series of log returns,
      # we need to come up with a series of portfolio values

      0.upto(series.size1-1) { |i|
        row = series.row(i)
        row.map! { |e| Math.exp(e) } #convert to returns
        series.set_row(i, current_portfolio_value * row.cumprod)
      }

      # now, for each column, we need a mean and variance
      means = GSL::Vector.alloc(series.size2)
      stddevs = GSL::Vector.alloc(series.size2)

      0.upto(series.size2-1) { |i|
        column = series.column(i)
        means[i] = column.mean
        stddevs[i] = Math.sqrt(column.variance)
      }

      return {:means => means, :standard_deviations => stddevs}
    end

    private
    # compute the current weights of the portfolio
    def compute_weights
      Status.info("Computing portfolio weights")
      begin
        @weights = GSL::Vector.alloc(@tickers.size)
        0.upto(@tickers.size-1) { |i|
          @weights[i] = @number_of_shares[i] * @time_series[@tickers[i]][@dates[-1]]
        }

        @weights = (@weights / @weights.abs.sum)
      end unless !@weights.nil?
    end

    def compute_current_portfolio_value
      pval = 0
      0.upto(@tickers.size-1) { |i|
        pval = pval + @number_of_shares[i] * @time_series[@tickers[i]][@dates[-1]]
      }
      return pval
    end
    
    def compute_log_returns
      Status.info("Computing log returns")
      begin
        @log_returns = GSL::Matrix.alloc(@tickers.size, @dates.size-1)
        0.upto(@tickers.size-1) { |i|
          ticker = @tickers[i]
          1.upto(@dates.size-1) { |d|
            #OPTIMIZE: Possible optimization -- cache the computed log value?
            @log_returns[i,d-1] = Math.log(@time_series[ticker][@dates[d]]) -
                                  Math.log(@time_series[ticker][@dates[d-1]])
          }
        }
      end unless !@log_returns.nil?

    end
        
    # Assumes @log_returns is filled
    def compute_covariance_matrix
      Status.info("Computing covariance matrix")
      begin
        @covariance_matrix = GSL::Matrix.alloc(@tickers.size, @tickers.size)
        0.upto(@tickers.size-1) { |i|
          i.upto(@tickers.size-1) { |j|
            cov = GSL::Stats::covariance(@log_returns.row(i), @log_returns.row(j))
            @covariance_matrix[i,j] = cov
            @covariance_matrix[j,i] = cov #symmetric matrix
          }
        }
      end unless !@covariance_matrix.nil?
    end
        
    # Assumes @covariance_matrix is filled
    def compute_correlation_matrix
      Status.info("Computing correlation matrix")
      begin
        @correlation_matrix = GSL::Matrix.alloc(@tickers.size, @tickers.size)
        0.upto(@tickers.size-1) { |i|
          i.upto(@tickers.size-1) { |j|
            corr = @covariance_matrix[i,j] /
              Math.sqrt(@covariance_matrix[i,i] * @covariance_matrix[j,j])
            @correlation_matrix[i,j] = corr
            @correlation_matrix[j,i] = corr #symmetric matrix
          }
        }
      end unless !@correlation_matrix.nil?
    end
  end
end