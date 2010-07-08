module Portfolio
  module Risk

    def self.marginal_contribution_to_volatility(portfolio_log_returns, factor_log_returns, window, step_size)
      # get log returns and translate them to % returns
      factor_returns = factor_log_returns.map { |e| Math.exp(e) - 1.0 }
      portfolio_returns = portfolio_log_returns.map { |e| Math.exp(e) - 1.0 }

      raise "Not enough information to analyze" if portfolio_returns.size < window
      
      n = portfolio_returns.size
      steps = ((n-window)/step_size).floor
      marginal_contributions = GSL::Matrix.alloc(factor_returns.size1, steps)

      factor_returns.size1.times { |i|
        steps.times { |j|
          holding_returns =  factor_returns.row(i).get(j*step_size, window)
          current_portfolio_returns = portfolio_returns.get(j*step_size, window)
          marginal_contributions[i,j] = 
                  GSL::Stats::correlation(holding_returns, current_portfolio_returns) *
                              Math.sqrt(holding_returns.variance)
        }
      }
      return marginal_contributions
    end

    def self.contributions_to_volatility(portfolio_state, factor_log_returns, window, step_size, marginal_contributions = nil)
      marginal_contributions = marginal_contribution_to_volatility(portfolio_state.to_log_returns,
                    factor_log_returns, window, step_size) if marginal_contributions.nil?

      weights = portfolio_state.weights_over_time

      nassets = marginal_contributions.size1
      nreadings = marginal_contributions.size2
      contributions = GSL::Matrix.alloc(nassets, nreadings)
      nreadings.times { |t|
        nassets.times { |i|
          contributions[i,t] = weights[i, t*step_size] * marginal_contributions[i, t]
        }
      }

      return contributions
    end

    def self.upside_downside_capture(portfolio_state, benchmark, window = nil, step = nil)

      raise "Must define both window and step" if window.nil? ^ step.nil?
      
      benchmark_state = Portfolio::State.new(benchmark)
      dates = portfolio_state.dates & benchmark_state.dates

      shared_portfolio_state = portfolio_state.select_dates(dates)
      shared_benchmark_state = benchmark_state.select_dates(dates)

      portfolio_returns = shared_portfolio_state.to_log_returns.to_a.map { |e| Math.exp(e) }
      benchmark_returns = shared_benchmark_state.to_log_returns.to_a.map { |e| Math.exp(e) }

      if window.nil?
        benchmark_up = 1
        portfolio_up = 1
        benchmark_down = 1
        portfolio_down = 1
        benchmark_returns.zip(portfolio_returns).each { |b,p|
          if b > 1
            benchmark_up = benchmark_up * b
            portfolio_up = portfolio_up * p
          else
            benchmark_down = benchmark_down * b
            portfolio_down = portfolio_down * p
          end
        }

        p_dn = portfolio_down - 1.0
        b_dn = benchmark_down - 1.0
        capture_ratio = [ (1.0/(1.0 + p_dn) - 1.0) / (1.0/(1.0 + b_dn) - 1.0),
                              (portfolio_up - 1.0) / (benchmark_up - 1.0)]
        return [capture_ratio]
        
      else
        capture_ratios = []
        n = ((portfolio_returns.size - window)/step).floor
        n.times { |i|
          portfolio_window = portfolio_returns[i*step...i*step+window]
          benchmark_window = benchmark_returns[i*step...i*step+window]
          
          benchmark_up = 1
          portfolio_up = 1
          benchmark_down = 1
          portfolio_down = 1

          window.times { |i|
            b = benchmark_window[i]
            p = portfolio_window[i]
            if b > 1
              benchmark_up = benchmark_up * b
              portfolio_up = portfolio_up * p
            else
              benchmark_down = benchmark_down * b
              portfolio_down = portfolio_down * p
            end
          }

          # instead of just comparing % down, here, we identify the logarithmic
          # property of returns and losses, where a 50% loss requires a
          # 100% return.  So if our manager is down 20% and the market is down
          # 40%, we don't want to say we were only captured 50% downside.
          # We want to say we require only
          # 
          #    (1 / (1 - 0.2) - 1) / (1 / 1 - 0.5) - 1) = 25%
          #
          # of what the market requires to get back to parity
          #
          # so we reward managers who avoid losses more than those who match
          # upside but capture all of the downside.  

          p_dn = portfolio_down - 1.0
          b_dn = benchmark_down - 1.0
          capture_ratios << [ (1.0/(1.0 + p_dn) - 1.0) / (1.0/(1.0 + b_dn) - 1.0),
                              (portfolio_up - 1.0) / (benchmark_up - 1.0)]
        }
        return capture_ratios
      end
    end
  end
end