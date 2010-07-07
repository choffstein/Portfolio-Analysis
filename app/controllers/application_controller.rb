# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  # Scrub sensitive parameters from your log
  # filter_parameter_logging :password

  def render_status
    if request.xhr?
      status = Status.render
      render :text => status[1]
    end
  end


  def random_colors(n)
    colors = []
    step = 360.0 / n

    n.times { |i|
      r, g, b = hsv_to_rgb(step*i + rand*step/2, 0.5, 0.9)
      r = (r*255).floor
      g = (g*255).floor
      b = (b*255).floor
      s = rgb_to_string(r,g,b)
      colors << s
    }

    size = colors.size
    half_size = colors.size/2
    alternating_colors = colors[0...half_size].zip(colors[half_size...size]).flatten
    if size % 2 == 1
      alternating_colors = (alternating_colors[0...half_size] <<
                           colors[-1] <<
                           alternating_colors[half_size...size]).flatten
    end

    return alternating_colors[0...size]
  end

  def random_color
    s = rand(16777215).to_s(16)
    (6 - s.length).times {
      s = "0" + s
    }
    return s
  end

  #gray is 0-1
  def greyscale_to_rgb(grey)
    as_hex = (grey*256).floor.to_s(16)
    if as_hex.length < 2
      as_hex = "0" + as_hex
    end
    return (as_hex + as_hex + as_hex)
  end

  def hsv_to_rgb_string(h,s,v)
    r,g,b = hsv_to_rgb(h,s,v)
    r = (r*255).floor
    g = (g*255).floor
    b = (b*255).floor
    return rgb_to_string(r,g,b)
  end

  private
  def pad_color_string(s)
    if s.length < 2
      s = "0" + s
    end

    return s
  end

  def rgb_to_string(r, g, b)
    return pad_color_string(r.to_s(16)) +
             pad_color_string(g.to_s(16)) +
               pad_color_string(b.to_s(16))
  end

  def hsv_to_rgb(h,s,v)
    hi = (h / 60.0).floor % 6
    f =  (h / 60.0) - (h / 60.0).floor
    p = v * (1.0 - s)
    q = v * (1.0 - (f*s))
    t = v * (1.0 - ((1.0 - f) * s))
    return {
        0 => [v, t, p],
        1 => [q, v, p],
        2 => [p, v, t],
        3 => [p, q, v],
        4 => [t, p, v],
        5 => [v, p, q],
    }[hi]
  end
end
