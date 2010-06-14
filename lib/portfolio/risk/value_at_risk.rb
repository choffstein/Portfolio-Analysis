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

        z = Statistics2.pnormaldist(confidence_level)
        za = z + 
             (1/6)*(z**2 - 1)*summary_stats[:skewness] +
             (1/24)*(z**3 - 3*z)*summary_stats[:kurtosis] -
             (1/36)*(2*z**3 - 5*z)*summary_stats[:skewness]**2

        var = 1 - Math.exp(summary_stats[:mean] -
                                za * Math.sqrt(summary_stats[:variance]))

        normal_distribution = Rubystats::NormalDistribution.new(0,1)
        
        cvar = 1 - Math.exp(summary_stats[:mean] -
                                Math.sqrt(summary_stats[:variance]) *
                                normal_distribution.pdf(za) /
                                normal_distribution.cdf(za) )

        return {:var => var, :cvar => cvar}
      end
    end
  end
end