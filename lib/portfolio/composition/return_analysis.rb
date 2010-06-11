module Portfolio
  module Composition
    module ReturnAnalysis
        
      ## These are proxies for composition break-down
      SECTORS = {
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

      ASSETS = {
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

      STYLES = {
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
        weights = GSL::Vector.alloc(num_days)
        weights[num_days-1] = 1
            
        #find the weight such that weights drop near 0 for a given window size
        window = dates.size
        w = Math.exp(Math.log(0.0001) / window)
        (num_days-2).downto(0) { |i|
          weights[i] = w * weights[i+1]
        }

        c, cov, chisq, status = GSL::MultiFit::wlinear(factor_returns, weights, portfolio_state.log_returns)


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

        s += "<b>Strict (Quadratic Programming) Decomposition</b>: <br/>"
        s += x[:x].to_s + "<br/>" + x[:qp].to_s + "<br/><i>" + x[:exit_code].to_s + "</i><br/>"

        s += "<br/><b>Return Concentration Decomposition: </b><br/>"
        #normalize the coefficients and take their proportion
        #abs_normalized_coeffs = (c / Math.sqrt(c * c.transpose)).abs
        #proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum
        abs_normalized_coeffs = (c / Math.sqrt(c * c.transpose)).abs
        proportions = abs_normalized_coeffs / abs_normalized_coeffs.sum


        0.upto(num_factors-1) { |i|
          s += "#{factors.keys[i]}: #{proportions[i] * 100}%<br/>"
        }

        #Two extremes for style box allocation
        #   1) 100% in one box (variance = ((1 - 1/9)^2 + 8*(0 - 1/9)^2) / 9 ) -- we want a infinitely small point
        #   2) 1/9 in each box (variance = 0) -- we want a unit circle
        styleBoxes = GSL::Matrix[[-1,  1],
          [ 0,  1],
          [ 1,  1],
          [-1,  0],
          [ 0,  0],
          [ 1,  0],
          [-1, -1],
          [ 0, -1],
          [ 1, -1]];

        max = 72.0 / 729.0
        if proportions.size == styleBoxes.size1
          loc = proportions * styleBoxes
          s += "Style Box Location: #{loc}<br/>"
          s += "Size: #{1 - proportions.var / max}<br/>"
        end

        #calculate our epsilon values for our predictors
        eps = weights.map { |v| Math.sqrt(v) } * (daily_fund_returns - factor_returns * c)

        # find the weighted return variance (note, note the same as wvariance())
        weighted_return_variance = 0
        0.upto(num_factors-1) { |i|
          weighted_return_variance += (c[i]**2) * cov[i,i]
          0.upto(num_factors-1) { |j|
            weighted_return_variance += 2*c[i]*c[j]*cov[i,j] unless i == j
          }
        }
        weighted_return_variance += eps.var

        s += "<br/><br/><b>Risk Weight:</b><br/>"
        risks = GSL::Vector.alloc(num_factors)
        0.upto(num_factors-1) { |i|
          risk = (c[i]**2)*cov[i,i]
          0.upto(num_factors-1) { |j|
            risk += c[i]*c[j]*cov[i,j] unless i == j
          }
          risks[i] = risk * 100 / weighted_return_variance
        }
        0.upto(num_factors-1) { |i|
          s += "#{factors.keys[i]}: #{risks[i]}%<br/>"
        }
        s += "Idiosyncratic Risk: #{(100 - risks.sum)}%<br/>"

        return s
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