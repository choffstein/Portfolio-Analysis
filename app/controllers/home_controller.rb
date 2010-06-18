class HomeController < ApplicationController
  def index
    if !params[:ticker].nil?
      @c = Company.first(:conditions => {:ticker => params[:ticker].downcase})
      if @c.nil?
        @c = Company.new({:ticker => params[:ticker]})
        @c.save!
      end

      @jumps = Statistics::Tests.jump_detection(@c.log_returns)
    else
      render :text => "Please enter a ticker"
    end
  end

  def risk_analysis
    if request.post?
      Rails.logger.info(params)
      data_file = DataFile.new(params[:upload])

      t = Time.now
      state = Portfolio::State.new({:tickers => date_file.tickers,
                                    :number_of_shares => date_file.shares})
      sliced_state = state.slice(state.dates.size - 1000) # 5 years
      composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(sliced_state)

      total = Time.now - t
    
      render :text => "#{composite_risk} (computed in #{total}s)"
    end
  end

  def state_test
  end
end
