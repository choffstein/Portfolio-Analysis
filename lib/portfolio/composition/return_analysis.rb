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
        'Real Estate' => 'VNQ'
      }

      ASSET_PROXIES = {
        'U.S. Equities' => 'SPY',
        'EAFE Equities' => 'EFA',
        'Emerging Market Equities' => 'VWO',

        'International (Ex-US) Treasuries' => 'BWX',
        'Corporate Bonds' => 'JNK',
        'U.S. Short Term Treasuries (1-3)' => 'SHY',
        'U.S. Long Term Treasuries (20+)' => 'TLT',

        'Commodities' => 'DBC',
        
        'International Real Estate' => 'RWX'
      }

      STYLE_PROXIES = {
        'Large Cap Value' => 'VTV',
        #'Large Cap Blend' => 'VV',
        'Large Cap Growth' => 'VUG',

        'Mid Cap Value' => 'VOE',
        #'Mid Cap Blend' => 'VO',
        'Mid Cap Growth' => 'VOT',

        'Small Cap Value' => 'VBR',
        #'Small Cap Blend' => 'VB',
        'Small Cap Growth' => 'VBK'
      }

      def self.composition_by_factors(portfolio_state, factors, window_size=60, sampling_period=10)
        factors_state = Portfolio::State.new({:tickers => factors.values,
                              :number_of_shares => Array.new(factors.size, 1)})
        dates = portfolio_state.dates & factors_state.dates

        shared_portfolio_state = portfolio_state.select_dates(dates)
        shared_factors_state = factors_state.select_dates(dates)

        portfolio_log_returns = shared_portfolio_state.to_log_returns.to_a
        factor_log_returns = shared_factors_state.log_returns
            
        n = (dates.size - window_size) / sampling_period
        betas = GSL::Matrix.alloc(factors.size, n)
        r2 = []
        n.times { |i|
          #ax = b
          offset = i*sampling_period
          x = factor_log_returns.submatrix(0, offset, factors.size, window_size)
          b = GSL::Vector.alloc(*portfolio_log_returns[(offset...(offset+window_size))])

          c, cov, chisq, status = GSL::MultiFit::linear(x.transpose,b)

          #normalize the coefficients and take their proportion
          #abs_normalized_coeffs = (c / Math.sqrt(c * c.transpose)).abs
          #proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum
          abs_normalized_coeffs = c.normalize.abs
          proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum
          betas.set_column(i, proportions)

          # compute the r^2
          f = (x.transpose*c - b)
          sse = f * f.transpose
          y = (b - b.mean)
          sst = y * y.transpose

          r2 << (1.0 - sse/sst)
        }

        return {:betas => betas, :r2 => r2}
      end

      def self.proportions_to_style(proportions)
        #Two extremes for style box allocation
        #   1) 100% in one box (variance = ((1 - 1/9)^2 + 8*(0 - 1/9)^2) / 9 ) -- we want a infinitely small point
        #   2) 1/9 in each box (variance = 0) -- we want a unit circle
        style_boxes = GSL::Matrix[[-1,  1],
                                 #[ 0,  1],
                                  [ 1,  1],
                                  [-1,  0],
                                 #[ 0,  0],
                                  [ 1,  0],
                                  [-1, -1],
                                 #[ 0, -1],
                                  [ 1, -1]];

        max_variance = 72.0 / 729.0
        location = proportions.row * style_boxes
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