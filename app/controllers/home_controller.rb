class HomeController < ApplicationController
  def index
    if !params[:ticker].nil?
      @c = Company.first(:conditions => {:ticker => params[:ticker]})
      if @c.nil?
        @c = Company.new({:ticker => params[:ticker]})
        @c.save!
      end
    else
      render :text => "Please provide a ticker"
    end
  end
end
