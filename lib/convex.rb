# Must have qhull installed and available from the command line to use

module Convex
  def self.qhull(n, d, data_points)
    s = "#{n}\r\n#{d}\r\n"
    data_points.each { |d|
      (d.size-1).times { |i|
        s += "#{d[i]} "
      }
      s += "#{d[-1]}\r\n"
    }

    results = nil
    IO.popen('qconvex QJ i Fx', mode='r+') { |io|
      io.write s
      io.close_write
      results = io.read
    }

    data = results.split("\n")
    
    faces = []
    num_faces = data[0].to_i
    num_faces.times { |i|
      faces << data[i+1].split(' ').map { |e| e.to_i}
    }

    n_indices = data[num_faces+1].to_i
    indices = []
    n_indices.times { |i|
      indices << data[num_faces+2+i].to_i
    }
    
    return { :faces => faces, :indices => indices }
  end
end