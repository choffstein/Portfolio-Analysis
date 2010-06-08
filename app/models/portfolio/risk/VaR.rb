require 'lib/math/statistics.rb'

module Portfolio
    module Risk
        def self.value_at_risk(portfolio_state, portfolio_value, confidence=0.95)
            z_score = Statistics::Gaussian::z_score_from_p_value(confidence)
            
            weights = portfolio_state.current_weights
            position_size = weights * portfolio_value
            
            dollar_variance = position_size.row * portfolio_state.covariance_matrix * position_size.column
            dollar_volatilty = Math.sqrt(dollar_variance)
            
            return z_score * dollar_volatility
        end
    end
end