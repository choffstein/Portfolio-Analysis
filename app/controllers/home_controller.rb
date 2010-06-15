class HomeController < ApplicationController
  def index
    if !params[:ticker].nil?
      @c = Company.first(:conditions => {:ticker => params[:ticker].downcase})
      if @c.nil?
        @c = Company.new({:ticker => params[:ticker].downcase})
        @c.save!
      end

      @jumps = Statistics::Tests.jump_detection(@c.log_returns)
    else
      render :text => "Please enter a ticker"
    end
  end

  def state_test
    Portfolio::State.new({:tickers => %w{BAC GE JPM}, :number_of_shares => [20, 35, 15]})
  end
end
