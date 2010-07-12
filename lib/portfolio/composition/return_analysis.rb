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
        'Consumer Disc.' => 'XLY',
        'Real Estate' => 'VNQ'
      }

      WORLD_EQUITY_PROXIES = {
        'U.S.A' => 'IWV',
        'Europe' => 'VGK',
        'Russia' => 'RSX',
        'Latin America' => 'ILF',
        'Japan' => 'EWJ',
        'Pacific Ex-Japan' => 'EPP',
        'India' => 'INP'
      }

      ASSET_PROXIES = {
        'U.S. Equity' => 'IWV',
        'EAFA Equity' => 'EFA',
        'Emerging Equity' => 'VWO',
        'U.S. Bonds' => 'AGG',
        'Commodities' => 'DBC',
        'U.S. Real Estate' => 'VNQ'
      }

      STYLE_PROXIES = {
        'Large Cap Value' => 'VTV', #IWD
        'Large Cap Growth' => 'VUG', #IWF

        'Mid Cap Value' => 'VOE',
        'Mid Cap Growth' => 'VOT',

        'Small Cap Value' => 'VBR', #IWN
        'Small Cap Growth' => 'VBK' #IWO
      }

      RATE_PROXIES = {
        'High Credit' => 'BND',
        'Low Credit' => 'HYG',
        #'Long Interest' => 'CFT',
        #'Short Interest' => 'BSV',
        'Long Interest' => 'TLT',
        'Short Interest' => 'SHY'
      }

      def self.composition_by_factors(portfolio_state, factors, window_size=60, sampling_period=10)
        factors_state = Portfolio::State.new({:tickers => factors.values,
                              :number_of_shares => Array.new(factors.size, 1)})
        dates = portfolio_state.dates & factors_state.dates

        shared_portfolio_state = portfolio_state.select_dates(dates)
        shared_factors_state = factors_state.select_dates(dates)

        portfolio_log_returns = shared_portfolio_state.to_log_returns.to_a
        factor_log_returns = shared_factors_state.log_returns

        raise "Not enough information to analyze" if dates.size < window_size
            
        n = ((dates.size - window_size) / sampling_period).floor
        
        betas = GSL::Matrix.alloc(factors.size, n)
        r2 = []
        n.times { |i|
          #ax = b
          offset = i*sampling_period
          x = factor_log_returns.submatrix(0, offset, factors.size, window_size)
          b = GSL::Vector.alloc(*portfolio_log_returns[(offset...(offset+window_size))])

          c, = GSL::MultiFit::linear(x.transpose,b)

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
                                  [ 1,  1],
                                  [-1,  0],
                                  [ 1,  0],
                                  [-1, -1],
                                  [ 1, -1]];

        location = proportions.row * style_boxes

        return location
      end

      def self.proportions_to_rate_and_credit_sensitivity(proportions)
        #Two extremes for style box allocation
        #   1) 100% in one box (variance = ((1 - 1/9)^2 + 8*(0 - 1/9)^2) / 9 ) -- we want a infinitely small point
        #   2) 1/9 in each box (variance = 0) -- we want a unit circle
        style_boxes = GSL::Matrix[[0, 1],
                                  [0, -1],
                                  [1, 0],
                                  [-1, 0]];

        location =  (proportions.row * style_boxes)

        # we need to project from unit 'diamond' to unit square
        # aka (1/2, 1/2) should be stretched to (1,1)
        return location
      end

      def self.pca(portfolio_state)
        #compute the eigen-vals and eigen-vects
        eigen_values, eigen_vectors = portfolio_state.sample_correlation_matrix.eigen_symmv
        eigen_values.map! { |e| [e, 0.0].max }
        
        percent_variance = eigen_values.abs / eigen_values.abs.sum

        return [eigen_values, percent_variance, eigen_vectors]
      end
    end
  end
end