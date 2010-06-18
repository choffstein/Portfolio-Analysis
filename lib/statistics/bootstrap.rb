
module Statistics
  module Bootstrap

    private
    class WeightedArray < Array
      def initialize(other_array, weights)
        total_weights = weights.inject(0.0) { |t,e| t+e }
        proportions = weights.map { |e| e / total_weights }
        
        elements = other_array.zip(proportions)

        # construct an alias table for faster access
        @table = []
        
        n = elements.size
        elements.map! { |a,w| [a, w*(n-1)]}
        elements.sort! { |e1,e2| e1[1] <=> e2[1] }

        while elements.size > 2
          p = elements[0][1]
          elements[-1][1] -= p
          @table << [p, elements[0][0], elements[-1][0]]
          elements.delete_at(0)
          elements.sort! { |a,b| a[1] <=> b[1] }
        end

        p = elements[0][1]
        elements[-1][1] -= (1.0 - p) #subtract the complement
        @table << [p, elements[0][0], elements[-1][0]]
      end

      def random_element
        entry = @table[(Kernel.rand * @table.size).floor]
        if Kernel.rand < entry[0]
          return entry[1]
        else
          return entry[2]
        end
      end
    end

    public
    # reference http://www.smartfolio.com/theory/details/appendices/a/
    # TODO: Should this be weighted randoms?
    def self.block_bootstrap(returns, target_length, block_size = 20, n = 1000)
      raise "Target length must be even multiple of block size" unless (target_length % block_size == 0)

      returns_as_array = returns.to_a
      total_blocks = returns_as_array.size - block_size
      # ideally, we want to pick from the last 10 years (10*250 days),
      # which on a daily basis is a decay weight x solving
      #                              0.00001 = x**2500
      # =>                  log(0.0001)/2500 = log(x)
      # =>             e^(log(0.0001)/2500)) = x
      weight_factor = Math.exp(Math.log(0.0001)/2500.0)
      weights = (0..total_blocks).map { |i| weight_factor**i }.reverse

      blocks = []
      0.upto(total_blocks-1) { |i|
        blocks << returns_as_array[i...(i+block_size)]
      }
      num_blocks = blocks.size

      weighted_blocks = WeightedArray.new(blocks, weights)
      series = GSL::Matrix.alloc(n, target_length)
      0.upto(n-1) { |i|
        0.upto(target_length / block_size) { |j|
          random_block = weighted_blocks.random_element
          (j*block_size).upto((j+1)*block_size-1) { |k|
            series[i,j] = random_block[k-j*block_size]
          }
        }
      }

      means = GSL::Vector.alloc(n)
      variances = GSL::Vector.alloc(n)
      skews = GSL::Vector.alloc(n)
      kurtoses = GSL::Vector.alloc(n)

      0.upto(n-1) { |i|
        row = series.row(i)
        means[i] = row.mean
        variances[i] = row.variance_m(means[i])
        #sd = Math.sqrt(variances[i])
        skews[i] = row.skew #FIX: skew(means[i], sd)
        kurtoses[i] = row.kurtosis #FIX: kurtosis(means[i], sd)
      }
      return {
        :mean => means.mean,
        :variance => variances.mean,
        :skewness => skews.mean,
        :kurtosis => kurtoses.mean,
        :series => series
      }
    end
  end
end