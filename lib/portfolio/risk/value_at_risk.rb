module Portfolio
  module Risk
    module ValueAtRisk
      # Cornish Fisher Value-at-Risk uses a boot-strapping method
      # to more appropriately determine the summary statistics for
      # a series of excess log-returns, and then adjusts the standard
      # value at risk statistic for skew and kurtosis factors
      def self.cornish_fisher(log_returns, confidence_level=0.95)
        summary_stats = Statistics::Bootstrap.block_bootstrap(log_returns, 1000)

        Rails.logger.info(summary_stats)
        # one sided tail
        z = Statistics2.pnormaldist(confidence_level)

        # see http://www.riskglossary.com/link/cornish_fisher.htm
        za = z + 
             (1.0/6.0)*(z**2 - 1.0)*summary_stats[:skewness] +
             (1.0/24.0)*(z**3 - 3.0*z)*(summary_stats[:kurtosis]) -
             (1.0/36.0)*(2.0*(z**3) - 5.0*z)*(summary_stats[:skewness]**2)
        
        var = 1 - Math.exp(summary_stats[:mean] -
                  za * Math.sqrt(summary_stats[:variance]))

        normal_distribution = Rubystats::NormalDistribution.new(0.0, 1.0)
        
        cvar = 1 - Math.exp(summary_stats[:mean] -
                                Math.sqrt(summary_stats[:variance]) *
                                normal_distribution.pdf(za) /
                                normal_distribution.cdf(za))

        return {:var => var, :cvar => cvar}
      end

      # See "HotSpots and Hedges" paper by Litterman, Goldman Sachs
      def self.composite_risk(portfolio_state)
        Status.info('Computing composite risk')
        # log-returns are row oriented
        returns = portfolio_state.log_returns
        n = returns.size1
        
        vars = GSL::Vector.alloc(n)
        Status.info('Computing Cornish-Fisher VaRs')
        0.upto(n-1) { |i|
          value_at_risk = cornish_fisher(returns.row(i))
          Rails.logger.info(value_at_risk)
          vars[i] =  value_at_risk[:var]
        }

        weights = portfolio_state.weights

        # see how much each var contributes to the overall portfolio
        # we use the covariance matrix to incorporate the overlap
        Status.info('Computing Risk Composition')
        covariance_matrix = portfolio_state.covariance_matrix
        risks = GSL::Vector.alloc(n)
        0.upto(n-1) { |i|
          risks[i] = (vars[i]**2)*covariance_matrix[i,i]
          0.upto(n-1) { |j|
            risks[i] += vars[i] * vars[j] * 
                        covariance_matrix[i,j] unless i == j
          }
        }

        weighted_risks = risks * weights
        
        return (weighted_risks / weighted_risks.abs.sum)
      end
    end
  end
end