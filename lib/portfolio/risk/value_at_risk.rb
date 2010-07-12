module Portfolio
  module Risk

    Standard_Normal_Distribution = Rubystats::NormalDistribution.new(0.0, 1.0)

    module ValueAtRisk
      # Cornish Fisher Value-at-Risk uses a boot-strapping method
      # to more appropriately determine the summary statistics for
      # a series of excess log-returns, and then adjusts the standard
      # value at risk statistic for skew and kurtosis factors
      # 
      # See http://papers.ssrn.com/sol3/papers.cfm?abstract_id=1535933
      def self.cornish_fisher(log_returns, days = 1, confidence_level=0.99)
        block_size = 25
        series = Statistics::Bootstrap.block_bootstrap(log_returns, 1250, 25)

        n = series.size1

        # one sided tail
        z = Statistics2.pnormaldist(confidence_level)

        vars = GSL::Vector.alloc(n)
        cvars = GSL::Vector.alloc(n)
        n.times { |i|
          row = series.row(i)
          values = row.to_a.map { |i| log_returns.get(i.to_i, block_size).to_a }.flatten
          v = GSL::Vector[*values]

          #the row is daily log returns
          #we need to take the cumsum then 'days' differences
          cumulative = v.cumsum

          m = cumulative.size
          differences = cumulative.get(days, m-days) - cumulative.get(0, m-days)

          mean = differences.mean
          variance = differences.variance_m(mean)
          #sd = Math.sqrt(variances[i])
          skewness = differences.skew #FIX: skew(means[i], sd)
          kurtosis = differences.kurtosis #FIX: kurtosis(means[i], sd)

          # see http://www.riskglossary.com/link/cornish_fisher.htm
          za = z +
               (1.0/6.0)*(z**2 - 1.0)*skewness +
               (1.0/24.0)*(z**3 - 3.0*z)*kurtosis -
               (1.0/36.0)*(2.0*(z**3) - 5.0*z)*(skewness**2)

          stddev = Math.sqrt(variance)

          left_tail_cutoff = mean - za * stddev
 
          total_left_tail_prob = 0.5 * (1.0 +
                  Math.erf((left_tail_cutoff - mean) / Math.sqrt(2.0*variance)))
          k = (1.0 / Math.sqrt(2.0*Math::PI*variance)) / total_left_tail_prob
          f = GSL::Function.alloc{ |x|
            x * k * Math.exp(-((x-mean)**2) / (2.0*variance))
          }

          left_tail_average, = f.qagil(left_tail_cutoff)

          vars[i] = 1.0 - Math.exp(left_tail_cutoff)
          cvars[i] = 1.0 - Math.exp(left_tail_average)
        }

        return {:var => vars.mean, :cvar => cvars.mean}
      end

      # See "HotSpots and Hedges" paper by Litterman, Goldman Sachs
      def self.composite_risk(portfolio_state, days = 1)
        Status.info('Computing composite risk')
        # log-returns are row oriented
        returns = portfolio_state.log_returns
        n = returns.size1

        # now compute the marginal VaRs
        Status.info('Computing marginal VaRs')

        total_holdings = GSL::Vector.alloc(n)
        last_date = portfolio_state.dates[-1]
        n.times { |i|
          total_holdings[i] = portfolio_state.number_of_shares[i] *
            portfolio_state.time_series[portfolio_state.tickers[i]][last_date]
        }
        
        total_portfolio_value = portfolio_state.current_portfolio_value
        variance = portfolio_state.covariance_matrix * total_holdings.col

        portfolio_variance = total_holdings * variance
        beta = total_portfolio_value * variance / portfolio_variance

        Status.info("Computing Portfolio VaR")
        portfolio_vars = cornish_fisher(portfolio_state.to_log_returns, days)
        portfolio_var = portfolio_vars[:var] #* total_portfolio_value
        portfolio_cvar = portfolio_vars[:cvar] #* total_portfolio_value

        vars = GSL::Vector.alloc(n)
        cvars = GSL::Vector.alloc(n)
        n.times { |i|
          Status.info("Computing VaR for #{portfolio_state.tickers[i]} (#{i+1}/#{n})")
          value_at_risk = cornish_fisher(returns.row(i), days)
          vars[i] =  value_at_risk[:var]
          cvars[i] = value_at_risk[:cvar]
        }
        #vars = vars * total_holdings
        #cvars = cvars * total_holdings

        marginal_vars = beta * portfolio_var #/ total_portfolio_value
        
        return {
          :portfolio_var => portfolio_var,
          :portfolio_cvar => portfolio_cvar,
          :individual_vars => vars,
          :individual_cvars => cvars,
          :component_vars => portfolio_state.weights.col * marginal_vars, # * marginal_vars.col
          :marginal_vars =>  marginal_vars
        }
      end
    end
  end
end