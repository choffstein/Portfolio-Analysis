module Optimization
  class ParticleSwarmOptimization
    private

    # Our particles
    class Fly
      attr_accessor :position, :velocity, :current_fitness

      # Define the feature dimensions, feature limits, et cetera
      def initialize(feature_dimension, feature_limits,
          inertia, cognitive, social, teleportation)
        @position = GSL::Vector.alloc(feature_dimension)
        @velocity = GSL::Vector.alloc(feature_dimension)
        @velocity.set_all(0)

        @feature_limits = feature_limits

        @feature_limits.each_index { |i|
          @position[i] = randomize_feature(i)
        }

        @current_fitness = nil
        @fitness_max = nil
        @position_max = nil

        @inertia = inertia
        @cognitive = cognitive
        @social = social
        @teleportation = teleportation
      end

      def current_fitness=(other)
        @current_fitness = other
        update_fitness!
      end

      # update the position based on local and global best, as well as momentum factors
      def update!(global_best_features)

        @velocity = @inertia * @velocity +
                    @cognitive * rand * (@position_max - @position) +
                    @social * rand * (global_best_features - @position)

        #@velocity.each_index { |i|
        #  @velocity[i] = @inertia * @velocity[i] +
        #    @cognitive * rand * (@position_max[i] - @position[i]) +
        #    @social * rand * (global_best_features[i] - @position[i])
        #}

        @position = @position + @velocity
        @position.size.times { |i|
          if rand < @teleportation
            @position[i] = randomize_feature(i)
          end
        }

        # ensure we have not exceeded our feature limits
        @position.each_index { |i|
          if @position[i] < @feature_limits[i][0]
            @position[i] = @feature_limits[i][0]
          elsif @position[i] > @feature_limits[i][1]
            @position[i] = @feature_limits[i][1]
          end
        }
      end #end update!

      private

      def randomize_feature(i)
        # this won't work if feature limits are Infinity...
        @feature_limits[i][0] +
          (@feature_limits[i][1] - @feature_limits[i][0]) * rand
      end
      
      # update the best local fitness
      def update_fitness!
        if @fitness_max.nil?
          @fitness_max = @current_fitness
          @position_max = @position
        else
          if @current_fitness < @fitness_max
            @fitness_max = @current_fitness
            @position_max = @position
          end
        end
      end #end min_max_compare!
    end #end Fly definition

    public

    # The big function
    # Inputs:
    #   population_size: Number of particles you want in the swarm
    #   feature_dimension: How many features are in the problem
    #   feature_limits: What range are the features defined in (for initialization only)
    #   max_iterations: Number of iterations to perform
    #   inertia: How fast the particle will move in its current direction
    #   cognitive: How fast the particle moves towards its own personal max
    #   social: How fast the particle moves towards the global max
    #
    #   Returns the global best fitness and feature set

    DEFAULT_OPTIONS = { 
      :minimum_iterations => 250,
      :maximum_iterations => 10000,
      :maximum_stuck => 250,
      :absolute_tolerance => -Infinity
    }
    def self.optimize_over(population_size, feature_dimension, feature_limits,
        inertia, cognitive, social, teleportation,
        regeneration, options={})

      raise "Feature limit definition must be equal to feature size definition" unless feature_dimension == feature_limits.size
      raise "Must provide fitness-function as block" unless block_given?

      options = Utility::Options::set_default_options(options, DEFAULT_OPTIONS)

      # initialize our population
      @population = Array.new(population_size)
      @population.map! {
        Fly.new(feature_dimension, feature_limits,
          inertia, cognitive, social, teleportation)
      }

      global_best = nil
      global_best_features = nil

      iteration = 0
      stuck = 0
      begin
        # find the fitness of each fly and see if it is a local best
        @population.each { |fly|
          fly.current_fitness = yield fly.position.clone
        }

        # find the best fitness of the current swarm
        best_fitness_index = GSL::Vector[*@population.map {
            |fly| fly.current_fitness }].sort_index[0]
        best_fitness = @population[best_fitness_index].current_fitness

        # check to see if it is a global best
        if global_best.nil?
          global_best = best_fitness
          global_best_features = @population[best_fitness_index].position
        elsif best_fitness < global_best
          stuck = 0
          global_best = best_fitness
          global_best_features = @population[best_fitness_index].position

          Rails.logger.info(global_best)
        else
          stuck = stuck + 1
        end

        # update each fly with the global best feature set
        @population.each { |fly|
          fly.update!(global_best_features)
        }

        iteration = iteration + 1

        if rand < regeneration
          @population.map! {
          Fly.new(feature_dimension, feature_limits,
            inertia, cognitive, social, teleportation)
          }
        end

        iteration = iteration + 1

      end while (stuck < options[:maximum_stuck] &&
                global_best > options[:absolute_tolerance] &&
                iteration < options[:maximum_iterations]) ||
                iteration < options[:minimum_iterations]
                

      return [global_best, global_best_features]
    end #end optimize_over
  end #end ParticleSwarmOptimization definition
end
