module Portfolio
    module Composition
        def self.pca(portfolio_state)
            #compute the eigen-vals and eigen-vects
            eigen_values, eigen_vectors = portfolio_state.covariance_matrix.eigen_symmv
            percent_variance = eigenvalues / eigenvalues.sum
            
            return [eigen_values, percent_variance, eigen_vectors]
        end
    end
end