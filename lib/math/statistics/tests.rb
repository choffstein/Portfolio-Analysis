module Math
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
        c_n = Math.sqrt(2.0*Math.log(n))/c -
          (Math.log(Math::PI) + Math.log(Math.log(n)) /
            (2.0*n*Math.sqrt(2.0*Math.log(n))))

        s_n = 1.0 / (c*sqrt(2*Math.log(n)))

        jump_prob_max_quantile = -Math.log(-Math.log(1-alpha))

        identified_jumps = []

        0.upto(n-1) { |idx|
          sIdx = idx - k + 2
          eIdx = idx - 1

          test_return = log_returns[k]

          biPowerVar = 0.0
          sIdx.upto(eIdx) { |j|
            biPowerVar += log_returns[j].abs * log_returns[j-1].abs
          }
          biPowerVar = biPowerVar / (k-2)

          test_statistic = ((test_return/Math.sqrt(biPowerVar)).abs - c_n) / s_n
          identified_jumps << idx unless test_statistic < jump_prob_max_quantile
        }

        return identified_jumps
      end
    end
  end
end