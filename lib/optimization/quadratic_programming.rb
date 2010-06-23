# Author::    Corey M. Hoffstein  (corey@hoffstein.com)
# Copyright:: Copyright (c) 2010
# License::   Distributes under the same terms as Ruby

Inf = 1.0/0

# Function solves:
#
# min QP(x) = 0.5*x'Hx + f'x
#  x
#
# s.t.	a'x = b
#       LB[i] <= x[i] <= UB[i] for all i=1..n
#
# Using the Generalized SMO algorithm outline in 
#    S. Keerthi, E.G.Gilbert. Convergence of a Generalized SMO Algorithm for SVM Classifier Design. 
#    Technical Report CD-00-01, Control Division, Dept. of Mechanical and Production Engineering, 
#    National University of Singapore, 2000. http://citeseer.ist.psu.edu/keerthi00convergence.html
#
# x is the initial guess

=begin
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
=end

module Optimization
  module QuadraticProgramming
    
    DEFAULT_OPTIONS = {
      :max_iterations   => 10000,
      :tolerance        => 1e-32,
    }
    
    def self.generalized_smo(h, f, a, b, lb, ub, x, options={})
      ret = {
        :x => x,
        :exit_code => 0,
        :qp => nil
      }
     
      # set up our default algorithm options
      options = Utility::Options.set_default_options(options, DEFAULT_OPTIONS)
    
      n = ret[:x].length
    
      # The gradient in Hx + f
      gradient = h*ret[:x] + f
      diag_H = h.diagonal
	
      iterations = 0
      current_tolerance = Inf
      while ret[:exit_code] == 0
        iterations = iterations + 1
	    
        minF_up = Inf; maxF_low = -Inf
        u = 0; v = 0
	    
        f = gradient / a
	    
        (0...n).each { |i|
          if lb[i] < ret[:x][i] && ret[:x][i] < ub[i]
            if minF_up > f[i]
              minF_up = f[i]; u = i
            end
            if maxF_low < f[i]
              maxF_low = f[i]; v = i
            end
          elsif (a[i] > 0 && ret[:x][i] == lb[i]) || (a[i] < 0 && ret[:x][i] == ub[i])
            if minF_up > f[i]
              minF_up = f[i]; u = i
            end
          elsif (a[i] > 0 && ret[:x][i] == ub[i]) || (a[i] < 0 && ret[:x][i] == lb[i])
            if maxF_low < f[i]
              maxF_low = f[i]; v = i
            end
          end
	        
          tolerance = (maxF_low - minF_up).abs
          if tolerance > options[:tolerance]
            col_u = h.column(u)
            col_v = h.column(v)
	            
            if a[u] > 0
              tau_lb = (lb[u]-ret[:x][u])*a[u]
              tau_ub = (ub[u]-ret[:x][u])*a[u]
            else
              tau_ub = (lb[u]-ret[:x][u])*a[u]
              tau_lb = (ub[u]-ret[:x][u])*a[u]
            end
	            
            if a[v] > 0
              tau_lb = [tau_lb, (ret[:x][v]-ub[v])*a[v]].max
              tau_ub = [tau_ub, (ret[:x][v]-lb[v])*a[v]].min
            else
              tau_lb = [tau_lb, (ret[:x][v]-lb[v])*a[v]].max
              tau_ub = [tau_ub, (ret[:x][v]-ub[v])*a[v]].min
            end
	            
            tau = (gradient[v]/a[v] - gradient[u]/a[u]) /
              ((diag_H[u]/(a[u]**2) + diag_H[v])/(a[v]**2) - 2*col_u[v]/(a[u]*a[v]))
	            
            tau = [[tau, tau_lb].max, tau_ub].min
	            
            ret[:x][u] += tau/a[u]
            ret[:x][v] -= tau/a[v]
	            
            gradient = gradient + col_u*tau/a[u] - col_v*tau/a[v]
          else
            ret[:exit_code] = :tolerance
          end
        }
	    
        if iterations > options[:max_iterations]
          ret[:exit_code] = :maximum_iterations
        end
      end
    
      ret[:qp] = 0.5 * ret[:x].transpose * h * ret[:x] + f.transpose * ret[:x]

      return ret
    end
  end
end