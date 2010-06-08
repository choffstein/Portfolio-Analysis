# Author::    Corey M. Hoffstein  (corey@hoffstein.com)
# Copyright:: Copyright (c) 2010
# License::   Distributes under the same terms as Ruby

require 'statistics2'
require 'gsl'

module Math
  module Statistics
    module Gaussian
      # Solve for the normal z score from a p value
      def self.z_score_from_p_val(p)
        solver = Root::FSolver.alloc(Root::FSolver::BISECTION)
        func = GSL::Function.alloc { |x, params|      # Define a function to solve
          p = params[0]
          (Statistics2.normdist(x) - p)**2
        }
        func.set_params(p)
    
        solver.set(func, -6, 6)
        begin
          status = solver.iterate
          r = solver.root
          xl = solver.x_lower
          xu = solver.x_upper
          status = Root.test_interval(xl, xu, 0, 0.00001)   # Check convergence
          if status == GSL::SUCCESS
            return r
          end
        end while status != GSL::SUCCESS
      end
    end
  end
end