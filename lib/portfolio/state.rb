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
    attr_reader :companies
        
    def initialize(params = {})
      Status.info("Initializing portfolio state")
      @number_of_shares = params[:number_of_shares]
      @tickers = params[:tickers].map { |ticker| ticker.upcase}
            
      # check if the time series already exists
      if params[:time_series].nil?
        # find the shared dates between all tickers in the portfolio
        first = true
        @companies = {}
        keys = []
        Status.update("Loading company data")
        @tickers.each { |ticker|
          c = Company.new({:ticker => ticker})
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
        @companies = params[:companies]
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

      unless params[:sample_correlatfion_matrix].nil?
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
        :companies => @companies,
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
        :companies => @companies,
        :time_series => select_time_series
      }
                   
      return State.new(params)
    end
        
    #compute the portfolio log return vector
    def to_log_returns
      #shouldn't really need this...
      compute_log_returns unless !@log_returns.nil?
      compute_weights unless !@weights.nil?
      
      begin

        Status.info("Creating portfolio log returns")
        portfolio_value = self.portfolio_value_over_time
        n = portfolio_value.size
        log_portfolio_value = portfolio_value.map { |e| Math.log(e) }

        # using @log_returns,
        @portfolio_log_returns = log_portfolio_value.get(1,n-1) -
                                              log_portfolio_value.get(0,n-1)

      end unless !@portfolio_log_returns.nil?
      
      return @portfolio_log_returns
    end

    #FIX: This should be cached?
    def to_income_stream
      begin income = Hash.new(0.0)
        @tickers.size.times { |i|
          ticker = @tickers[i]
          shares = @number_of_shares[i]
          
          @companies[ticker].dividends.each { |k,v|
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
          row = series.row(j)
          values = row.to_a.map { |i| lr.get(i.to_i, block_size).to_a }.flatten.map { |e| Math.exp(e) }
          v = GSL::Vector[*values].cumprod
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
        row = series.row(j)
        values = row.to_a.map { |i| @portfolio_log_returns.get(i.to_i, block_size).to_a }.flatten.map { |e| Math.exp(e) }
        v = GSL::Vector[*values].cumprod
        returns[j] = (v[-1] ** (1.0/(periods / 250.0))) - 1 # annualize
      }

      means_variances << [Math.sqrt(returns.variance), returns.mean]

      return means_variances
    end

    def income_monte_carlo(periods_forward = 4, n = 10000)
      Status.info("Performing portfolio income monte-carlo simulation")
      historic_income = self.to_income_stream
      
      # take last 10 years of data from income stream -- 40 periods
      # ignore the latest quarter, because we are probably 'mid-quarter' and
      # therefore everything is skewed
      historic_income = historic_income.get((-[40, historic_income.size].min..-2).to_a)

      Rails.logger.info(historic_income.to_a)

      x = GSL::Vector.linspace(0, historic_income.size-1, historic_income.size)
      weights = x.map { |e| 0.982820599**e }.reverse
      weights = weights / weights.sum

      #income stream should have exponential growth over time -- so take log
      #so we can fit a linear estimation
      log_historic_income = historic_income.map { |v| Math.log(v) }

      c0, c1, cov00, cov01, cov11, = GSL::Fit::wlinear(x, weights, log_historic_income)

      distances = GSL::Vector.alloc(x.size)
      x.size.times { |i|
        est, = GSL::Fit::linear_est(i, c0, c1, cov00, cov01, cov11)
        distances[i] = log_historic_income[i] - est
      }
      stddev = Math.sqrt(distances.variance)
      
      r = GSL::Rng.alloc
      income = GSL::Matrix.alloc(n, periods_forward)

      estimates = GSL::Vector.alloc(periods_forward)
      periods_forward.times { |i|
        est, = GSL::Fit::linear_est(x.size + i, c0, c1, cov00, cov01, cov11)
        estimates[i] = est
      }

      n.times { |i|
        v = GSL::Vector.alloc(periods_forward)
        err = stddev * r.gaussian(1, periods_forward)
        income.set_row(i, estimates + err)
      }

      #get back to income stream values
      income.map! { |e| Math.exp(e) }
      
      # now, for each column, we need a mean and variance
      means = GSL::Vector.alloc(periods_forward)
      upside_stddevs = GSL::Vector.alloc(periods_forward)
      downside_stddevs = GSL::Vector.alloc(periods_forward)
      periods_forward.times { |i|
        column = income.column(i)
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

    def return_monte_carlo(periods_forward = 250, n = 10000, block_size = 10)
      Status.info("Performing return monte-carlo simulation on portfolio")

      log_returns = self.to_log_returns
      initial_value = compute_current_portfolio_value
      weight_factor = 1.0

      series = Statistics::Bootstrap::block_bootstrap(log_returns,
                                periods_forward, block_size, n, weight_factor)

      # given our current portfolio value and a series of log returns,
      # we need to come up with a series of portfolio values

      return_series = GSL::Matrix.alloc(n, periods_forward)

      series.size1.times { |i|
        row = series.row(i)
        values = row.to_a.map { |i| log_returns.get(i.to_i, block_size).to_a }.flatten.map { |e| Math.exp(e) }
        v = GSL::Vector[*values].cumprod
        return_series.set_row(i, initial_value * v)
      }

      # now, for each column, we need a mean and variance
      means = GSL::Vector.alloc(return_series.size2)
      upside_stddevs = GSL::Vector.alloc(return_series.size2)
      downside_stddevs = GSL::Vector.alloc(return_series.size2)
      return_series.size2.times { |i|
        column = return_series.column(i)
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

    def current_portfolio_value
      compute_current_portfolio_value
    end

    def portfolio_value_over_time
      begin
        @portfolio_value = GSL::Vector.alloc(@dates.size)
        @portfolio_value.set_all(0.0)

        @dates.size.times { |t|
          @tickers.size.times { |i|
            @portfolio_value[t] += @number_of_shares[i] *
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

    def expected_volatility(days = 250)
      block_size = 10
      log_returns = self.to_log_returns
      series = Statistics::Bootstrap::block_bootstrap(log_returns,
                                            days.to_i, block_size, 10000, 0.9999)

      volatilities = GSL::Vector.alloc(series.size1)
      series.size1.times { |j|
        row = series.row(j)

        values = GSL::Vector[*(row.to_a.map { |i| log_returns.get(i.to_i, block_size).to_a }.flatten.map)]
        annual_variance = Math.sqrt(values.variance / (1.0 / days)) #daily variance
        volatilities[j] = Math.exp(annual_variance) - 1.0
      }

      return volatilities.mean
    end

    def compute_draw_down_correlation
      compute_log_returns if @log_returns.nil?
      n = @log_returns.size1
      m = @log_returns.size2

      draw_downs = GSL::Matrix.alloc(n, m)
      n.times { |i|
        maximum = 0
        cumsum = 0

        m.times { |j|
          cumsum = cumsum + @log_returns[i,j]

          if cumsum > maximum
            maximum = cumsum
          end
          draw_downs[i,j] = cumsum - maximum
        }
      }

      draw_down_correlation_matrix = GSL::Matrix.alloc(n, n)
      n.times { |i|
        i.upto(n-1) { |j|
          corr = GSL::Stats::correlation(draw_downs.row(i), draw_downs.row(j))
          draw_down_correlation_matrix[i,j] = corr
          draw_down_correlation_matrix[j,i] = corr #symmetric matrix
        }
      }

      s = GSL::Matrix.alloc(n,n).set_all(0.0)
      xk = draw_down_correlation_matrix
      yk = nil
      begin
        yk = xk
        rk = yk - s

        lambda, q = rk.eigen_symmv
        lambda = GSL::Matrix.diagonal(lambda.map { |e| [e, 0.0].max })

        xk = q * lambda * q.transpose
        s = xk - rk
        xk.diagonal.set_all(1.0) #set diagonals to 1

      end while (xk - yk).norm > 1e-12

      return xk
    end
    
    private

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
        @tickers.size.times { |i|
          ticker = @tickers[i]
          ts = @time_series[ticker]
          1.upto(@dates.size-1) { |d|
            #OPTIMIZE: Possible optimization -- cache the computed log value?
            @log_returns[i,d-1] = Math.log(ts[@dates[d]]) - Math.log(ts[@dates[d-1]])
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
        n = @tickers.size
        @sample_correlation_matrix = GSL::Matrix.alloc(n, n)
        n.times { |i|
          i.upto(n-1) { |j|
            corr = @sample_covariance_matrix[i,j] /
              Math.sqrt(@sample_covariance_matrix[i,i] * @sample_covariance_matrix[j,j])
            @sample_correlation_matrix[i,j] = corr
            @sample_correlation_matrix[j,i] = corr #symmetric matrix
          }
        }


        # here, we need to apply changes to the sample correlation matrix
        # to converge to the nearest stable correlation matrix
        #
        # Properties of correlation matrix
        #
        # symmetric
        # 1s on the diagonal
        # off-diagonal elements between −1 and 1
        # eigenvalues nonnegative
        #       

        s = GSL::Matrix.alloc(n,n).set_all(0.0)
        xk = @sample_correlation_matrix
        yk = nil
        begin
          yk = xk
          rk = yk - s

          lambda, q = rk.eigen_symmv
          lambda = GSL::Matrix.diagonal(lambda.map { |e| [e, 0.0].max })

          xk = q * lambda * q.transpose
          s = xk - rk
          xk.diagonal.set_all(1.0) #set diagonals to 1
          
        end while (xk - yk).norm > 1e-12
        
        @sample_correlation_matrix = xk
        
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


        diagonal = @sample_covariance_matrix.diagonal.map { |e| Math.sqrt(e) }
        f = r_bar * diagonal.col * diagonal

        
        num_dates = @log_returns.size2.to_i

        # construct our shrinkage intensity, delta
        pi = GSL::Matrix.alloc(n, n)
        n.times { |i|
          n.times { |j|
            r =        ((@log_returns.row(i) - mean_log_returns[i]) *
                        (@log_returns.row(j) - mean_log_returns[j]) -
                                @sample_covariance_matrix[i,j])

            pi[i,j] = (r * r.col) / num_dates.to_f
          }
        }

        pi_hat = pi.to_v.sum

        rho_hat = pi.trace
        n.times { |i|
          n.times { |j|
            rho_hat += (r_bar / 2.0) *
                    (Math.sqrt(@sample_covariance_matrix[j,j] /
                           @sample_covariance_matrix[i,i]) *
                             asyscov_est(mean_log_returns, i, i, j) +
                     Math.sqrt(@sample_covariance_matrix[i,i] /
                           @sample_covariance_matrix[j,j]) *
                             asyscov_est(mean_log_returns, j, i, j)) unless i == j
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

    def asyscov_est(v, k, i, j)
          yj = (@log_returns.row(j) - v[j]).map { |e| e ** 2} - @sample_covariance_matrix[k,k]
          yij = (@log_returns.row(i) - v[i]) * (@log_returns.row(j) - v[j]) - @sample_covariance_matrix[i,j]

          return yj * yij.col / yj.size.to_f
    end
  end
end