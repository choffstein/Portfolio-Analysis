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
        benchmark_returns.each { |b|
          if b > 1
            benchmark_up = benchmark_up * b
          else
            benchmark_down = benchmark_down * b
          end
        }

        portfolio_returns.each { |p|
          if p > 1
            portfolio_up = portfolio_up * p
          else
            portfolio_down = portfolio_down * p
          end
        }

        capture_ratio = [(portfolio_down - 1.0) / (benchmark_down - 1.0),
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
          benchmark_window.each { |b|
            if b > 1
              benchmark_up = benchmark_up * b
            else
              benchmark_down = benchmark_down * b
            end
          }

          portfolio_window.each { |p|
            if p > 1
              portfolio_up = portfolio_up * p
            else
              portfolio_down = portfolio_down * p
            end
          }

          capture_ratios << [(portfolio_down - 1.0) / (benchmark_down - 1.0),
                              (portfolio_up - 1.0) / (benchmark_up - 1.0)]
        }
        return capture_ratios
      end
    end
  end
end