
module Statistics
  module Bootstrap

    Cache = Struct.new(:weight, :length, :series)
    @@cache = Cache.new(nil, nil, nil)

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

      def random_elements_with_vec(v)
        n = v.size / 2
        entries = Array.new(n)
        n.times { |i|
          entry = @table[(v[i*2] * @table.size).floor]
          entries[i] = v[i*2 + 1] < entry[0] ? entry[1] : entry[2]
        }

        return entries
      end
    end

    public
    # reference http://www.smartfolio.com/theory/details/appendices/a/
    # Ideally here, we would do a weighted random system where the weight
    # choice becomes smoother the further we get away from the present
    #
    # ideally, we want to pick from the last 10 years (10*250 days),
    # which on a daily basis is a decay weight x solving
    #                              0.00001 = x**2500
    # =>                  log(0.0001)/2500 = log(x)
    # =>             e^(log(0.0001)/2500)) = x
    def self.block_bootstrap(returns, target_length, block_size = 20,
                                      n = 2500, weight_factor = 0.998401279)
      raise "Target length must be even multiple of block size" unless (target_length % block_size == 0)

      returns_as_array = returns.to_a
      total_blocks = returns_as_array.size - block_size
      

      #TODO: weighted blocks should be recomputed every time a block is
      #      placed?

      # cache the series so we don't have to construct it multiple times if
      # we are doing it with the same weight factor
      if @@cache[:weight].nil? || weight_factor != @@cache[:weight] || @@cache[:length] != total_blocks
        weights = (0..total_blocks).map { |i| weight_factor**i }.reverse
        blocks = []
        total_blocks.times { |i|
          blocks << returns_as_array[i...(i+block_size)]
        }
        @@cache[:series] = WeightedArray.new(blocks, weights)
        @@cache[:weight] = weight_factor
        @@cache[:length] = total_blocks
      end


      r = GSL::Rng.alloc
      series = GSL::Matrix.alloc(n, target_length)
      n.times { |i|
        #overwrite our row with random blocks
        v = r.uniform(2 * target_length / block_size)
        
        row = @@cache[:series].random_elements_with_vec(v)
        #transform it to a vector
        vec = GSL::Vector[*row.flatten]
        #insert it into the series matrix
        series.set_row(i, vec)
      }
      return series
    end
  end
end