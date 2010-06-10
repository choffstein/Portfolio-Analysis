require 'statistics2'
require 'rubystats'

module Portfolio
  module Risk
    def self.gaussian_value_at_risk(portfolio_state, portfolio_value,
                                    confidence=0.95)
      z_score = Statistics2.pnormaldist(confidence)

      weights = portfolio_state.current_weights
      position_size = weights * portfolio_value
            
      dollar_variance = position_size.row * portfolio_state.covariance_matrix * position_size.column
      dollar_volatilty = Math.sqrt(dollar_variance)
            
      return z_score * dollar_volatility
    end

    # reference http://www.smartfolio.com/theory/details/risk_tools/techniques/
    def self.cornish_fisher_value_at_risk(portfolio_state, portfolio_value,
                                          confidence=0.95, target_length=1000)

      z_score = Statistics2.pnormaldist(confidence)

      return_vector = portfolio_state.to_return_vector

      # boot-strap our sample returns
      return_stats = Math::Statistics.block_bootstrap(return_vector,
                                                      target_length)
                                                    
      # adjust our z-score for skewness and kurtosis
      z_a = z_score +
            (1/6)*(z_score**2 - 1)*return_stats[:skewness] +
            (1/24)*(z_score**3 - 3*z_score)*return_stats[:kurtosis] -
            (1/36)*(2*z_score**3 - 5*z_score)*(return_stats[:skewness]**2)


      normal_distribution = Rubystats::NormalDistribution.new(0,1)

      return { :VaR => 1 - Math.exp(return_stats[:mean] -
                              z_a * Math.sqrt(return_stats[:variance]),
               :CVaR => 1 - Math.exp(return_stats[:mean] -
                              Math.sqrt(return_stats[:variance]) *
                              normal_distribution.pdf(z_a) /
                              normal_distribution.cdf(z_a))
             }
    end
  end
end