
module Statistics
  module Bootstrap
    # reference http://www.smartfolio.com/theory/details/appendices/a/
    def self.block_bootstrap(returns, target_length, block_size=50, n=100)
      raise "Target length must be even multiple of block size" unless target_length % block_size == 0

      blocks = []
      0.upto(returns.size-(block_size+1)) { |i|
        blocks << returns[i...i+block_size]
      }
      num_blocks = blocks.size

      series = GSL::Matrix.alloc(n, target_length)
      0.upto(n-1) { |i|
        0.upto(target_length / block_size) { |j|
          random_block = blocks[rand(num_blocks)]
          series[i][j*block_size...(j+1)*block_size] = random_block
        }
      }

      v = series.to_v #turn our matrix into a long vector of returns
      return {
        :mean => v.mean,
        :variance => v.variance,
        :skewness => v.skew,
        :kurtosis => v.kurtosis,
        :series => series
      }
    end
  end
end