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
end
