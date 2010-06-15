module Portfolio
  module Composition
    module ReturnAnalysis
        
      ## These are proxies for composition break-down
      SECTOR_PROXIES = {
        'Materials' => 'XLB',
        'Energy' => 'XLE',
        'Financials' => 'XLF',
        'Industrials' => 'XLI',
        'Technology' => 'XLK',
        'Consumer Staples' => 'XLP',
        'Utilities' => 'XLU',
        'Health Care' => 'XLV',
        'Consumer Discretionary' => 'XLY',
        'Telecom' => 'TTH',
        'Real Estate' => 'VNQ'
      }

      ASSET_PROXIES = {
        'U.S. Domestic Equities' => 'SPY',
        'European Equities' => 'VGK',
        'Emerging Markets' => 'VWO',
        'Pacific (ex. Japan)' => 'EPP',
        'Latin America' => 'ILF',

        'US Dollar' => 'UUP',
        'Euro' => 'FXE',
        'Yen' => 'FXY',
        'Australian Dollar' => 'FXA',
        'Canadian Dollar' => 'FXC',
        'Chinese Yuan' => 'CYB',
        'Emerging Markets' => 'CEW',

        'Emerging Market Sovereign Debt' => 'PCY',
        'International Treasury' => 'BWX',
        'High Yield Corporates' => 'JNK',
        'U.S. Long Term Treasuries' => 'TLT',

        'Agriculture' => 'DBA',
        'Base Metals' => 'DBB',
        'Energy' => 'DBE',
        'Oil' => 'DBO',
        'Precious Metals' => 'DBP',

        'U.S. Real Estate' => 'VNQ',
        'International Real Estate' => 'RWX'
      }

      STYLE_PROXIES = {
        'Large Cap Value' => 'VTV',
        'Large Cap Blend' => 'VV',
        'Large Cap Growth' => 'VUG',

        'Mid Cap Value' => 'VOE',
        'Mid Cap Blend' => 'VO',
        'Mid Cap Growth' => 'VOT',

        'Small Cap Value' => 'VBR',
        'Small Cap Blend' => 'VB',
        'Small Cap Growth' => 'VBK'
      }

      def self.composition_by_factors(portfolio_state, factors)
            
        factors_state = Portfolio::State.new(factors.values)
        dates = portfolio_state.dates & factors_state.dates
            
        shared_portfolio_state = portfolio_state.select_dates(dates)
        shared_factors_state = factors_state.select_dates(dates)
            
        #Exponentially weighted to drop off rapidly after `window` days
        weights = GSL::Vector.alloc(dates.size)
        weights[dates.size-1] = 1
            
        #find the weight such that weights drop near 0 for a given window size
        window = dates.size
        w = Math.exp(Math.log(0.0001) / window)
        (dates.size-2).downto(0) { |i|
          weights[i] = w * weights[i+1]
        }

        c, cov, chisq, status =
               GSL::MultiFit::wlinear(shared_factors_state.log_returns, weights,
                                             shared_portfolio_state.log_returns)

        num_factors = factors.values.size
        lb = GSL::Vector.alloc(num_factors)
        lb.set_all(0.0)

        ub = GSL::Vector.alloc(num_factors)
        ub.set_all(1.0)

        a = GSL::Vector.alloc(num_factors)
        a.set_all(1.0)

        initial_guess = GSL::Vector.alloc(num_factors)
        initial_guess.set_all(1.0/num_factors)
        x = QuadraticProgramming::generalized_smo(factor_returns.transpose * factor_returns,
          -factor_returns.transpose * daily_fund_returns,
          a, 1.0, lb.col, ub.col, initial_guess.col)

        #normalize the coefficients and take their proportion
        #abs_normalized_coeffs = (c / Math.sqrt(c * c.transpose)).abs
        #proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum
        abs_normalized_coeffs = (c / Math.sqrt(c * c.transpose)).abs
        proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum

        return proportions
      end

      def self.proportions_to_style(proportions)
        #Two extremes for style box allocation
        #   1) 100% in one box (variance = ((1 - 1/9)^2 + 8*(0 - 1/9)^2) / 9 ) -- we want a infinitely small point
        #   2) 1/9 in each box (variance = 0) -- we want a unit circle
        style_boxes = GSL::Matrix[[-1,  1],
          [ 0,  1],
          [ 1,  1],
          [-1,  0],
          [ 0,  0],
          [ 1,  0],
          [-1, -1],
          [ 0, -1],
          [ 1, -1]];

        max_variance = 72.0 / 729.0
        location = proportions * style_boxes
        size = 1 - proportions.var / max_variance

        return {:location => location, :size => size}
      end

      def self.pca(portfolio_state)
        #compute the eigen-vals and eigen-vects
        eigen_values, eigen_vectors = portfolio_state.covariance_matrix.eigen_symmv
        percent_variance = eigenvalues / eigenvalues.sum

        return [eigen_values, percent_variance, eigen_vectors]
      end
    end
  end
end