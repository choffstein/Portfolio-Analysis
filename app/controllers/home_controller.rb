class HomeController < ApplicationController
  def index
    if !params[:ticker].nil?
      @c = Company.first(:conditions => {:ticker => params[:ticker]})
      if @c.nil?
        @c = Company.new({:ticker => params[:ticker]})
        @c.save!
      end

      @jumps = Statistics::Tests.jump_detection(@c.log_returns)
    else
      render :text => "Please enter a ticker"
    end
  end
end
