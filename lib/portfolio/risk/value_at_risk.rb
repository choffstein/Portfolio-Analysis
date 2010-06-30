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
        series = Statistics::Bootstrap.block_bootstrap(log_returns, 1000)

        n = series.size1
        
        means = GSL::Vector.alloc(n)
        variances = GSL::Vector.alloc(n)
        skews = GSL::Vector.alloc(n)
        kurtoses = GSL::Vector.alloc(n)

        n.times { |i|
          row = series.row(i)

          #the row is daily log returns
          #we need to take the cumsum then 'days' differences
          cumulative = row.cumsum

          m = cumulative.size
          differences = cumulative.get(days, m-days) - cumulative.get(0, m-days)

          means[i] = differences.mean
          variances[i] = differences.variance_m(means[i])
          #sd = Math.sqrt(variances[i])
          skews[i] = differences.skew #FIX: skew(means[i], sd)
          kurtoses[i] = differences.kurtosis #FIX: kurtosis(means[i], sd)
        }

        mean = means.mean
        variance = variances.mean
        skewness = skews.mean
        kurtosis = kurtoses.mean

        # one sided tail
        z = Statistics2.pnormaldist(confidence_level)

        # see http://www.riskglossary.com/link/cornish_fisher.htm
        za = z + 
             (1.0/6.0)*(z**2 - 1.0)*skewness +
             (1.0/24.0)*(z**3 - 3.0*z)*kurtosis -
             (1.0/36.0)*(2.0*(z**3) - 5.0*z)*(skewness**2)
        
        var = 1.0 - Math.exp(mean - za * Math.sqrt(variance))

        cvars = []
        n.times { |i|
          row = series.row(i)
          cumulative = row.cumsum
          m = cumulative.size
          differences = cumulative.get(days, m-days) - cumulative.get(0, m-days)

          pct_differences = differences.map { |e| 1.0 - Math.exp(e) }
          cvar_pct_differences = pct_differences.to_a.select { |e| e > var }
          local_cvar = cvar_pct_differences.inject(0.0) { |s,v| s + v } / cvar_pct_differences.size
          cvars << local_cvar unless local_cvar.nan?
        }

        cvar = cvars.inject(0.0) { |s,v| s + v } / cvars.size

        return {:var => var, :cvar => cvar}
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
        portfolio_var = portfolio_vars[:var] * total_portfolio_value
        portfolio_cvar = portfolio_vars[:cvar] * total_portfolio_value

        vars = GSL::Vector.alloc(n)
        cvars = GSL::Vector.alloc(n)
        0.upto(n-1) { |i|
          Status.info("Computing VaR for #{portfolio_state.tickers[i]} (#{i+1}/#{n})")
          value_at_risk = cornish_fisher(returns.row(i), days)
          vars[i] =  value_at_risk[:var]
          cvars[i] = value_at_risk[:cvar]
        }
        vars = vars * total_holdings
        cvars = cvars * total_holdings

        # see how much each var contributes to the overall portfolio
        # we use the covariance matrix to incorporate the overlap
        Status.info('Computing Risk Composition')
        covariance_matrix = portfolio_state.covariance_matrix.map { |e| Math.exp(e)-1 }
        risks = GSL::Vector.alloc(n)
        n.times { |i|
          risks[i] = vars[i]
          n.times { |j|
            risks[i] += vars[j] * covariance_matrix[i,j] unless i == j
          }
        }
        
        return {
          :portfolio_var => portfolio_var,
          :portfolio_cvar => portfolio_cvar,
          :individual_vars => vars,
          :individual_cvars => cvars,
          :proportion_of_var => risks / risks.abs.sum,
          :marginal_vars => beta * portfolio_var / total_portfolio_value
        }
      end
    end
  end
end