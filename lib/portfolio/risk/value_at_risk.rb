require 'statistics2'
require 'rubystats'

module Portfolio
  module Risk
    module ValueAtRisk
      # Cornish Fisher Value-at-Risk uses a boot-strapping method
      # to more appropriately determine the summary statistics for
      # a series of excess log-returns, and then adjusts the standard
      # value at risk statistic for skew and kurtosis factors
      def self.cornish_fisher(log_returns, confidence_level=0.95)
        summary_stats = Statistics::Bootstrap.block_bootstrap(log_returns, 1000)

        # one sided tail
        z = Statistics2.pnormaldist(confidence_level)
        
        za = z + 
             (1.0/6)*(z**2 - 1)*summary_stats[:skewness] +
             (1.0/24)*(z**3 - 3.0*z)*summary_stats[:kurtosis] -
             (1.0/36)*(2.0*(z**3) - 5.0*z)*(summary_stats[:skewness]**2)

        var = 1 - Math.exp(summary_stats[:mean] -
                                za * Math.sqrt(summary_stats[:variance]))

        normal_distribution = Rubystats::NormalDistribution.new(0,1)
        
        cvar = 1 - Math.exp(summary_stats[:mean] -
                                Math.sqrt(summary_stats[:variance]) *
                                normal_distribution.pdf(za) /
                                normal_distribution.cdf(za) )

        return {:var => var, :cvar => cvar}
      end

      # See "HotSpots and Hedges" paper by Litterman, Goldman Sachs
      def self.composite_risk(portfolio_state)
        # log-returns are row oriented
        returns = portfolio_state.log_returns
        n = returns.size1
        
        vars = GSL::Vector.alloc(n)
        0.upto(n-1) { |i|
          vars[i] = cornish_fisher(returns.row(i))
        }

        weights = portfolio_state.current_weights

        # see how much each var contributes to the overall portfolio
        # we use the covariance matrix to incorporate the overlap
        covariance_matrix = portfolio_state.covariance_matrix
        risks = GSL::Vector.alloc(n)
        0.upto(n-1) { |i|
          risks[i] = vars[i]**2 * covariance_matrix[i,i]
          0.upto(n-1) { |j|
            risks[i] += vars[i]*vars[j]*covariance_matrix[i,j] unless i == j
          }
        }

        # multiply each risk by the portfolios exposure to it
        weighted_risks = risks * weights

        weighted_risks / sum(weighted_risks)
      end
    end
  end
end