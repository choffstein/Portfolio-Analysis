# implement hierarchical clustering
# use centroid of cluster for distance when new clusters are created
# to create more balanced clusters

module Cluster
  Infinity = 1.0/0
  
  def self.hierarchical(original_data_matrix, target_clusters = nil, max_distance = Infinity)
    data_matrix = original_data_matrix.clone

    clusters = []
    # define our initial clusters
    data_matrix.size1.times { |i|
      clusters << [i]
    }

    target_clusters = Math.sqrt(original_data_matrix.size1) if target_clusters.nil?

    while clusters.size > target_clusters
      distance_matrix = data_to_distance(data_matrix, clusters.map { |e| e.size} )
      n = distance_matrix.size1

      # find the minimum pair
      current_minimum = Infinity
      current_minimum_indices = nil
      n.times { |i|
        n.times { |j|
          if i != j && distance_matrix[i,j] < current_minimum
            current_minimum = distance_matrix[i,j]
            current_minimum_indices = [i,j]
          end
        }
      }

      if current_minimum < max_distance
        i, j = current_minimum_indices
        row_to_replace = [i,j].min
        row_to_remove = [i,j].max

        # merge the clusters in our list
        # put the two together
        clusters[row_to_replace] = clusters[i] + clusters[j]
        clusters.delete_at(row_to_remove)

        # redefine our distance matrix.  Replace the ith row/column with the minimum
        # of the ith and jth rows.
        # remove the jth row/column
        new_data_matrix = GSL::Matrix.alloc(n-1, original_data_matrix.size2)

        clusters.size.times { |i|
          cluster = clusters[i]
          v = original_data_matrix.row(cluster[0])
          1.upto(cluster.size-1) { |j|
            v = v + original_data_matrix.row(cluster[j])
          }

          v = v / cluster.size #find center of cluster

          new_data_matrix.set_row(i, v)
        }

        data_matrix = new_data_matrix
      else
        break #our minimum distance < our max distance
      end
    end

    return clusters
  end

  private
  def self.data_to_distance(data_matrix, size_vector = nil)

    n = data_matrix.size1
    size_vector = Array.new(n, 1.0) if size_vector.nil?

    distance_matrix = GSL::Matrix.alloc(n, n)
    n.times { |i|
      distance_matrix[i,i] = 0.0
      (i+1).upto(n-1) { |j|
        row_a = data_matrix.row(i)
        row_b = data_matrix.row(j)
        # make larger clusters 'heavier,' so that we get more even
        # attribution across clusters
        distance_matrix[i,j] = (row_a - row_b).nrm2 * Math.sqrt((size_vector[i] + size_vector[j]))
        distance_matrix[j,i] = distance_matrix[i,j]
      }
    }
    
    return distance_matrix
  end
end