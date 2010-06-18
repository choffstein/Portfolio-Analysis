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

  def monte_carlo
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          state = Portfolio::State.new({:tickers => session[:portfolio].tickers,
                          :number_of_shares => session[:portfolio].shares})
          sliced_state = state.slice(state.dates.size - 1000) # 5 years
          mc_series = sliced_state.monte_carlo

          g = Gruff::Line.new(mc_series.size2)
          g.title = "Monte Carlo Simulation"
          0.upto(mc_series.size1-1) { |i|
            g.data("Series #{i}", mc_series.row(i).to_a)
          }

          send_data(g.to_blob,
                    :disposition => 'inline',
                    :type => 'image/png',
                    :filename => "mc_simulation.png")
        end
      }
    end
  end

  def risk_analysis
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          t = Time.now
          state = Portfolio::State.new({:tickers => session[:portfolio].tickers,
              :number_of_shares => session[:portfolio].shares})
          sliced_state = state.slice(state.dates.size - 1000) # 5 years
          composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(sliced_state)

          total = Time.now - t

          render :text => "#{composite_risk} (computed in #{total}s)"
        end
      }
    end
  end

  def state_test
    @portfolio = session[:portfolio]
    Rails.logger.info(@portfolio.tickers.zip(@portfolio.shares)) unless @portfolio.nil?

    if request.post?
      Rails.logger.info(params)
      session[:portfolio] = DataFile.new(params[:portfolio])
    end
  end
end
