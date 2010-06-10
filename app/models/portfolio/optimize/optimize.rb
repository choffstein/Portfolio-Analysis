require 'gsl'
require 'utility/set_default_options'

module Portfolio
    module Optimize
        # optimize (minimize) portfolio weights over a GSL::Function
        DEFAULT_OPTIONS = { :test_size => 1e-16,
                            :max_iterations => 10000 }
                            
        def self.optimize_over_simplex(portfolio_state, f,
                                          number_of_parameters, options = nil)
            options = Utility::Options.set_default_options(options, DEFAULT_OPTIONS)
            
            minimizer = GSL::MultiMin::Minimizer.alloc("nmsimplex", number_of_parameters)
            
            step_size = GSL::Vector.alloc(number_of_parameters)
            step_size.set_all(0.01)
            
            minimizer.set(f, portfolio_state.weights, step_size)
            
            iter = 0
            begin
                iter += 1
                status = minimizer.iterate()
                status = minimizer.test_size(options[:test_size])
                if status == GSL::SUCCESS
                    return minimizer.x
                end
            end while status == GSL::CONTINUE and iter < options[:max_iterations]
        end

=begin
        def self.optimize_over_pso(portfolio_state, number_of_parameters, options = nil, &blk)
          pso = Math::Optimization::ParticleSwarmOptimization.optimize_over(
                           population_size, feature_dimension, feature_limits,
                           inertia, cognitive, social, options) {
                                                      |*args| blk.call(*args) }
        end
=end
    end
end