
module Statistics
  module Tests
    # takes a time series of log returns
    #
    # Relevant Academic Work:
    #
    # Jumps in Financial Markets: A New Nonparametric Test and Jump Dynamics
    # Suzanne S. Lee and Per A. Mykland
    #
    # k recommendations
    # Time Frame:  1 Week | 1 Day | 1 Hour | 30 Min | 15 Min | 5 Min
    # K         :     7   |   16  |   78   |  110   |  156   |  270
    #
    # Returns the index of each jump detected
    def self.jump_detection(log_returns, k=16, alpha=0.01)
      n = log_returns.length

      c = Math.sqrt(2.0 / Math::PI)

      s_n = 1.0 / (c*Math.sqrt(2.0*Math.log(n)))
      c_n = Math.sqrt(2.0*Math.log(n))/c -
            (Math.log(Math::PI) + Math.log(Math.log(n))) * 0.5 * s_n

      jump_prob_max_quantile = -Math.log(-Math.log(1.0-alpha))

      identified_jumps = []

      bi_power_var_cache = {} # instead of recomputing biPowerVar each time,
                            # just cache the result so
      0.upto(n-1) { |idx|
        sIdx = idx - k + 2
        eIdx = idx - 1

        test_return = log_returns[idx]

        bi_power_var = 0.0
        if bi_power_var_cache[idx-1].nil?
          sIdx.upto(eIdx) { |j|
            bi_power_var += log_returns[j].abs * log_returns[j-1].abs
          }
          bi_power_var = bi_power_var / (k-2)
          bi_power_var_cache[idx] = bi_power_var
        else
          bi_power_var = bi_power_var_cache[idx-1] -
                          log_returns[sIdx].abs * log_returns[sIdx-1].abs +
                          log_returns[eIdx].abs * log_returns[eIdx-1].abs
        end

        test_statistic = ((test_return/Math.sqrt(bi_power_var)).abs - c_n) / s_n
        identified_jumps << (idx+1) unless test_statistic < jump_prob_max_quantile
      }

      return identified_jumps
    end
  end
end