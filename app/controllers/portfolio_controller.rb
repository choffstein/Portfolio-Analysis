class PortfolioController < ApplicationController
  def index
    redirect_to :action => :analyze
  end

  def analyze
    @portfolio = session[:portfolio]
  end

  def upload_portfolio
    if request.post?
      Rails.logger.info(params)
      session[:portfolio] = DataFile.new(params[:portfolio])
      redirect_to :action => :analyze
    end
  end


  def company
    @company = Company.find(:first,
                          :conditions => {:ticker => params[:ticker].downcase})
  end

  def monte_carlo
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          state = Portfolio::State.new({:tickers => session[:portfolio].tickers,
              :number_of_shares => session[:portfolio].shares})

          offset = (state.dates.size - 1000) < 0 ? 0 : (state.dates.size - 1000)
          sliced_state = state.slice(offset) # 5 years
          mc_series = sliced_state.monte_carlo

          x_data = (1..100).to_a

          means = (mc_series[:means]).to_a
          two_std_above = (mc_series[:means] +
              2.0 * mc_series[:standard_deviations]).to_a
          two_std_below = (mc_series[:means] -
              2.0 * mc_series[:standard_deviations]).to_a

          Status.info("Generating graphic")
          lc = GoogleChart::LineChart.new
          lc.width = 600
          lc.height = 300
          lc.title = "100 Day Projection (Monte Carlo Simulation with n = 1000)"

          lc.data "Mean", means, 'FF6600', "5,0,0"
          lc.data "+2 Std. Devs", two_std_above, '858585', "3,6,3"
          lc.data "-2 Std. Devs", two_std_below, '858585', "3,6,3"

          lc.encoding = :extended
          lc.show_legend = true

          lc.axis :left, :range => [two_std_below.min.floor,
            two_std_above.max.ceil],
          :color => '000000', :font_size => 16, :alignment => :center

          lc.axis :bottom, :range => [x_data[0].floor, x_data[-1].ceil],
          :color => '000000', :font_size => 16, :alignment => :center

          extras = {
            :chg => "10,10,1,5"
          }
          #Rails.logger.info(lc.to_url)

          render :text => "<img src=\"#{lc.to_url(extras)}\"/>"
        end
      }
    end
  end

  def risk_decomposition
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          t = Time.now
          tickers = session[:portfolio].tickers
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => session[:portfolio].shares})
          offset = (state.dates.size - 1000) < 0 ? 0 : (state.dates.size - 1000)
          sliced_state = state.slice(offset) # 5 years
          composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(sliced_state)

          total = Time.now - t
=begin
          GoogleChart::PieChart.new do |pc|
            pc.height = 400
            pc.width = 600
            pc.title = "Risk Decomposition"
            #pc.show_legend = true

            0.upto(tickers.size-1) { |i|
              value = (composite_risk[i] * 10000).round.to_f / 10000
              pc.data "#{tickers[i]}", 
                       composite_risk[i].abs,
                       random_color
            }
            Rails.logger.info(pc.to_url({:chdlp => 'b'}))
            
            pc.write_to("public/images/portfolio/risk-decomposition", {:chdlp => 'b'})
            render :inline => "<%= image_tag(\"portfolio/risk-decomposition.png\") %>"
          end
=end

          @chart = GoogleVisualr::PieChart.new
          @chart.add_column('string', 'Ticker')
          @chart.add_column('number', 'Value at Risk Contribution')
          @chart.add_rows(composite_risk.size)
          composite_risk.size.times { |i|
            @chart.set_value(i, 0, tickers[i])
            @chart.set_value(i, 1, composite_risk[i])
          }
          options = { :width => 600, :height => 400,
                      :title => 'Risk Decomposition', :is3D => true }
          options.each_pair { | key, value |
            @chart.send "#{key}=", value
          }

          render :inline => "<%= @chart.render('risk_results') %>"
        end
      }
    end
  end

  def sector_return_decomposition
    respond_to do |wants|
      wants.js {

        tickers = session[:portfolio].tickers
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => session[:portfolio].shares})
        offset = (state.dates.size - 1000) < 0 ? 0 : (state.dates.size - 1000)
        sliced_state = state.slice(offset) # ~5 years

        factors = Portfolio::Composition::ReturnAnalysis::SECTOR_PROXIES
        return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors)
        #get a return composition on the sliced-state

        betas = return_values[:betas]
        r_squared = return_values[:r2]

        sa = GoogleChart::StackedArea.new
        sa.title = "Return Decomposition"
        sa.width = 600
        sa.height = 300
        sa.show_legend = true
        sa.encoding = :extended

        factor_names = factors.keys
        betas.size1.times { |i|
          sa.data "#{factor_names[i]}", betas.row(i).to_a, random_color
        }

        sa.axis(:left) do |axis|
          axis.alignment = :center
          axis.color = "000000"
          axis.font_size = 16
          axis.range = 0..1
        end

        sa.axis :bottom, :alignment => :center, :color => "000000",
        :font_size => 16, :range => [1,1000]

        lc = GoogleChart::LineChart.new
        lc.title = "Return Decomposition"
        lc.width = 600
        lc.height = 150
        lc.title = "R-Squared"

        lc.data "r-squared", r_squared, '000000', "1,0,0"

        lc.encoding = :simple
        lc.show_legend = true

        lc.axis :left, :range => [0, 1],
        :color => '000000', :font_size => 16, :alignment => :center

        lc.axis :bottom, :range => [1,1000],
        :color => '000000', :font_size => 16, :alignment => :center

        #FIX: This seems like a rather ugly way to do this
        sa.write_to("public/images/portfolio/sector_return_decomposition", {:chdlp => 'b'})
        lc.write_to("public/images/portfolio/sector_r-squared", {:chdlp => 'b'})

        #send_data(sa.fetch_image, :type => 'image/png',
        #          :file_name => 'Return Composition', :disposition => 'inline')
        render :inline => "<%= image_tag(\"portfolio/sector_return_decomposition.png\") %><br/><%= image_tag(\"portfolio/sector_r-squared.png\") %>"
      }
    end
  end

  def style_return_decomposition
    respond_to do |wants|
      wants.js {

        tickers = session[:portfolio].tickers
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => session[:portfolio].shares})
        offset = (state.dates.size - 1000) < 0 ? 0 : (state.dates.size - 1000)
        sliced_state = state.slice(offset) # ~5 years

        factors = Portfolio::Composition::ReturnAnalysis::STYLE_PROXIES
        return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors)
        #get a return composition on the sliced-state

        betas = return_values[:betas]
        r_squared = return_values[:r2]

        points = []
        betas.size2.times { |i|
          break_down = Portfolio::Composition::ReturnAnalysis::proportions_to_style(betas.column(i))
          points << break_down[:location].to_a
        }

        total_points = points.size
        colors = []
        (total_points-1).times { |i|
          colors << greyscale_to_rgb(i / total_points.to_f)
        }
        colors.unshift("FF0000") #current time is red

        # Scatter Plot
        sc = GoogleChart::ScatterPlot.new
        sc.width = 400
        sc.height = 400
        sc.title = "Style Analysis"
        sc.data "", points, colors.reverse
        sc.encoding = :extended

        #sc.data "Style Points", points, colors
        sc.max_x = 1
        sc.max_y = 1
        sc.min_x = -1
        sc.min_y = -1
        sc.point_sizes Array.new(points.size,1)

        sc.axis(:bottom, :range => -1..1, :labels => ['Value', 'Blend', 'Growth'])
        sc.axis(:left, :range => -1..1, :labels => ['Small', 'Mid', 'Large'])
        sc.axis(:top, :range => -1..1, :labels => ['Value', 'Blend', 'Growth'])
        sc.axis(:right, :range => -1..1, :labels => ['Small', 'Mid', 'Large'])

        #FIX: This seems like a rather ugly way to do this
        extras = {
          :chg => "33.33,33.33,1,5"
        }
        sc.write_to("public/images/portfolio/style_return_decomposition", extras)

        #send_data(sa.fetch_image, :type => 'image/png',
        #          :file_name => 'Return Composition', :disposition => 'inline')
        render :inline => "<%= image_tag(\"portfolio/style_return_decomposition.png\") %>"
      }
    end
  end
end
