module Portfolio
  # This class encompasses the current state of the portfolio
  # over a given time-frame.
  class State
    attr_reader :tickers
    attr_reader :time_series
    attr_reader :dates
    attr_reader :log_returns
    attr_reader :covariance_matrix
    attr_reader :sample_covariance_matrix
    attr_reader :sample_correlation_matrix
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
      unless params[:log_returns].nil?
        @log_returns = params[:log_returns]
      else
        compute_log_returns
      end

      unless params[:sample_covariance_matrix].nil?
        @sample_covariance_matrix  = params[:sample_covariance_matrix]
      else
        compute_sample_covariance_matrix
      end

      unless params[:sample_correlation_matrix].nil?
        @sample_correlation_matrix = params[:sample_correlation_matrix]
      else
        compute_sample_correlation_matrix
      end

      unless params[:covariance_matrix].nil?
        @covariance_matrix = params[:covariance_matrix]
      else
        compute_covariance_matrix
      end
      
      @weights = compute_weights
    end
        
    # dates is an array of dates
    def select_dates(dates)
      Status.info("Computing portfolio time-slice")
      
      select_time_series = @tickers.each_with_object({}) { |ticker, hsh|
        hsh[ticker] = dates.each_with_object({}) { |date, hsh|
          hsh[date] = @time_series[ticker][date]
        }
      }
      
      params = {  :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :time_series => select_time_series
      }
            
      return State.new(params)
    end
        
    #computes a slice by time index
    def slice(offset, window=nil)
      window ||= @dates.size - offset
      
      raise "offset must be greater than or equal to zero" unless offset >= 0
      raise "window size must be greater than zero" unless window > 0
      raise "offset + window must be less than total number of dates" unless offset+window <= @dates.size

      Status.info("Computing portfolio time-slice")
      dates = @dates[offset...offset+window]
      #Rails.logger.info(dates)

      select_time_series = @tickers.each_with_object({}) { |ticker, hsh|
        hsh[ticker] = dates.each_with_object({}) { |date, hsh|
          hsh[date] = @time_series[ticker][date]
        }
      }
            
      params = { :tickers => @tickers,
        :dates => dates,
        :number_of_shares => @number_of_shares,
        :time_series => select_time_series
      }
                   
      return State.new(params)
    end
        
    #compute the portfolio log return vector
    def to_log_returns
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

    #FIX: This should be cached?
    def to_income_stream
      begin income = Hash.new(0.0)
        @tickers.size.times { |i|
          ticker = @tickers[i]
          shares = @number_of_shares[i]

          c = Company.first(:conditions => {:ticker => ticker})

          c.dividends.each { |k,v|
            income[k] += shares * v
          }
        }

        income = Hash[income.sort]
        @income_stream = GSL::Vector.alloc(income.size)
        i = 0
        income.each { |key, value|
          @income_stream[i] = value
          i = i + 1
        }
      end if @income_stream.nil?

      return @income_stream
    end

    def risk_to_return(periods = 1250, n = 2500, block_size = 25, weight_factor = 0.998401279)
      means_variances = []
      @log_returns.size1.times { |i|
        Status.info("Performing Risk vs Return simulation on #{@tickers[i]}")
        lr = @log_returns.row(i)
        series = Statistics::Bootstrap::block_bootstrap(lr, periods,
                                block_size, n, weight_factor)

        returns = GSL::Vector.alloc(series.size1)
        series.size1.times { |j|
          v = series.row(j).map { |e| Math.exp(e) }.cumprod
          returns[j] = (v[-1] ** (1.0/(periods / 250.0))) - 1 # annualize
        }

        means_variances << [Math.sqrt(returns.variance), returns.mean]
      }

      Status.info("Performing Risk vs Return simulation on Portfolio")
      # compute the portfolio mean / variance
      series = Statistics::Bootstrap::block_bootstrap(self.to_log_returns,
                              periods, block_size, n, weight_factor)

      returns = GSL::Vector.alloc(series.size1)
      series.size1.times { |j|
        v = series.row(j).map { |e| Math.exp(e) }.cumprod
        returns[j] = (v[-1] ** (1.0/(periods / 250.0))) - 1 # annualize
      }

      means_variances << [Math.sqrt(returns.variance), returns.mean]

      return means_variances
    end

    def income_monte_carlo(periods_forward = 4, n = 10000, block_size = 1)
      Status.info("Performing portfolio income monte-carlo simulation")
      historic_income = self.to_income_stream
      
      # transform the income stream into log returns
      current_income = historic_income[-1]
      log_historic_income = historic_income.map { |v| Math.log(v) }

      length = log_historic_income.size
      log_returns = log_historic_income.get(1,length-1) -
                                    log_historic_income.get(0,length-1)
      
      # drastically over-weight recent income growth versus historic
      return monte_carlo(log_returns, current_income,
                          periods_forward, n, block_size, 0.85)
    end

    def return_monte_carlo(periods_forward = 250, n = 10000, block_size = 10)
      Status.info("Performing return monte-carlo simulation on portfolio")
      return monte_carlo(self.to_log_returns, compute_current_portfolio_value,
                          periods_forward, n, block_size, 0.9995)
    end

    def portfolio_value_over_time
      begin
        @portfolio_value = GSL::Vector.alloc(@dates.size)
        @portfolio_value.set_all(0.0)

        @dates.size.times { |t|
          @tickers.size.times { |i|
            @portfolio_value += @number_of_shares[i] *
                                          @time_series[@tickers[i]][@dates[t]]
          }
        }
      end if @portfolio_value.nil?
      return @portfolio_value
    end

    def weights_over_time
      begin
        portfolio_value = self.portfolio_value_over_time
        @weights_over_time = GSL::Matrix.alloc(@tickers.size, @dates.size)
        @dates.size.times { |t|
          @tickers.size.times { |i|
            @weights_over_time[i,t] = @number_of_shares[i] *
                                      @time_series[@tickers[i]][@dates[t]] /
                                      @portfolio_value[t]
          }
        }
        
      end if @weights_over_time.nil?
      return @weights_over_time
    end
    
    private

    def monte_carlo(log_returns, initial_value, periods_forward = 1250,
                      n = 2500, block_size = 25, weight_factor = 1.0)
      series = Statistics::Bootstrap::block_bootstrap(log_returns,
                                periods_forward, block_size, n, weight_factor)

      # given our current portfolio value and a series of log returns,
      # we need to come up with a series of portfolio values

      series.size1.times { |i|
        row = series.row(i)
        row.map! { |e| Math.exp(e) } #convert to returns
        series.set_row(i, initial_value * row.cumprod)
      }

      # now, for each column, we need a mean and variance
      means = GSL::Vector.alloc(series.size2)
      upside_stddevs = GSL::Vector.alloc(series.size2)
      downside_stddevs = GSL::Vector.alloc(series.size2)
      series.size2.times { |i|
        column = series.column(i)
        m = column.mean
        means[i] = m

        offset_column = (column - m).to_a
        upside_array = offset_column.map { |x| x > 0 ? x : 0 }
        downside_array = offset_column.map { |x| x < 0 ? x : 0 }

        upside_vector = GSL::Vector.alloc(upside_array)
        downside_vector = GSL::Vector.alloc(downside_array)

        upside_stddevs[i] = Math.sqrt(upside_vector.variance)
        downside_stddevs[i] = Math.sqrt(downside_vector.variance)
      }

      return {:means => means,
              :upside_standard_deviations => upside_stddevs,
              :downside_standard_deviations => downside_stddevs }
    end

    # compute the current weights of the portfolio
    def compute_weights
      Status.info("Computing portfolio weights")
      begin
        @weights = GSL::Vector.alloc(@tickers.size)
        @tickers.size.times { |i|
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
    def compute_sample_covariance_matrix
      Status.info("Computing sample covariance matrix")
      begin
        @sample_covariance_matrix = GSL::Matrix.alloc(@tickers.size, @tickers.size)
        0.upto(@tickers.size-1) { |i|
          i.upto(@tickers.size-1) { |j|
            cov = GSL::Stats::covariance(@log_returns.row(i), @log_returns.row(j))
            @sample_covariance_matrix[i,j] = cov
            @sample_covariance_matrix[j,i] = cov #symmetric matrix
          }
        }
      end unless !@sample_covariance_matrix.nil?
    end
        
    # Assumes @covariance_matrix is filled
    def compute_sample_correlation_matrix
      Status.info("Computing correlation matrix")
      begin
        @sample_correlation_matrix = GSL::Matrix.alloc(@tickers.size, @tickers.size)
        0.upto(@tickers.size-1) { |i|
          i.upto(@tickers.size-1) { |j|
            corr = @sample_covariance_matrix[i,j] /
              Math.sqrt(@sample_covariance_matrix[i,i] * @sample_covariance_matrix[j,j])
            @sample_correlation_matrix[i,j] = corr
            @sample_correlation_matrix[j,i] = corr #symmetric matrix
          }
        }
      end unless !@sample_correlation_matrix.nil?
    end

    # Applies the Shrinkage Estimator from
    # "Honey, I Shrunk the Sample Covariance Matrix"
    #  Ledoit, Wolf (2003)
    def compute_covariance_matrix
      Status.info("Shrinking covariance matrix")
      begin
        mean_log_returns = GSL::Vector.alloc(@tickers.size)
        @tickers.size.times { |i|
          mean_log_returns[i] = @log_returns.row(i).mean
        }

        n = @tickers.size
        @covariance_matrix = GSL::Matrix.alloc(n, n)

        r_bar = (@sample_correlation_matrix.upper -
                GSL::Matrix.diagonal(@sample_correlation_matrix.diagonal)).to_v.sum
        r_bar = (r_bar * 2.0) / (n*(n-1))

        #0.upto(@tickers.size-2) { |i|
        #  (i+1).upto(@tickers.size-1) { |j|
        #    r_bar = r_bar + @sample_covariance_matrix[i,j]
        #  }
        #}

        # construct our shrinkage target
        f = GSL::Matrix.alloc(n, n)
        n.times { |i|
          f[i,i] = @sample_covariance_matrix[i,i]
          (i+1).upto(n-1) { |j|
            f[i,j] = r_bar * Math.sqrt(@sample_covariance_matrix[i,i] *
                                       @sample_covariance_matrix[j,j])
            f[j,i] = f[i,j]
          }
        }

        num_dates = @log_returns.size2.to_i

        # construct our shrinkage intensity, delta
        pi = GSL::Matrix.alloc(n, n)
        n.times { |i|
          n.times { |j|
            pi[i,j] = 0
            num_dates.times { |t|
              pi[i,j] += (((@log_returns[i,t] - mean_log_returns[i]) *
                          (@log_returns[j,t] - mean_log_returns[j])) -
                                      @sample_covariance_matrix[i,j]) ** 2
            }
            pi[i,j] = pi[i,j] / num_dates.to_f
          }
        }

        pi_hat = pi.to_v.sum
        #Rails.logger.info("Pi-Hat: #{pi_hat}")

        rho_hat = pi.trace
        n.times { |i|
          n.times { |j|
            rho_hat += (r_bar / 2.0) *
                    (Math.sqrt(@sample_covariance_matrix[j,j] /
                           @sample_covariance_matrix[i,i]) *
                             asyscov_est(mean_log_returns, num_dates, i, i, j) +
                     Math.sqrt(@sample_covariance_matrix[i,i] /
                           @sample_covariance_matrix[j,j]) *
                             asyscov_est(mean_log_returns, num_dates, j, i, j)) unless i == j
          }
        }
        #Rails.logger.info("Rho-Hat: #{rho_hat}")

        gamma_hat = (f - @sample_covariance_matrix).norm ** 2
        #n.times { |i|
        #  n.times { |j|
        #    gamma_hat += f[i,j] - @sample_covariance_matrix[i,j] ** 2
        #  }
        #}
        #Rails.logger.info("Gamma-Hat: #{gamma_hat}")

        kappa_hat = (pi_hat - rho_hat) / gamma_hat
        #Rails.logger.info("Kappa-Hat: #{kappa_hat}")

        begin
          delta_hat = [0.0, [kappa_hat / num_dates, 1.0].min].max
        rescue
          delta_hat = 0.0 #one stock portfolio -- corner case
        end
        #Rails.logger.info("Delta-Hat: #{delta_hat}")

        @covariance_matrix = delta_hat * f + (1.0 - delta_hat)*@sample_covariance_matrix

      end unless !@covariance_matrix.nil?
    end

    def asyscov_est(v, n, k, i, j)
          s = 0
          n.times { |t|
            s = s + ((@log_returns[j,t] - v[j])**2 - @sample_covariance_matrix[k,k]) *
                    ((@log_returns[i,t] - v[i])*(@log_returns[j,t] - v[j]) - @sample_covariance_matrix[i,j])
          }
          s = s / n.to_f
          return s
    end
  end
end