class PortfolioController < ApplicationController
  def index
    redirect_to :action => :analyze
  end

  def analyze
    @portfolio = session[:portfolio]
  end

  def upload_portfolio
    if request.post?
      #Rails.logger.info(params)
      session[:portfolio] = DataFile.new(params[:portfolio])
      redirect_to :action => :analyze
    end
  end


  def company
    ticker = params[:ticker].downcase
    @company = Company.find(:first,
      :conditions => {:ticker => ticker})
    if @company.nil?
      #if we can't find the company, create a new one (and download the data)
      @company = Company.new({:ticker => ticker})
      @company.save!
    end

    @company.dividends
  end

  def volatility_analysis
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          tickers = session[:portfolio].tickers.sort
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => session[:portfolio].shares})

          window_size = 60
          sampling_period = 20
          
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # 5 years

          marginal_contributions = Portfolio::Risk.marginal_contribution_to_volatility(sliced_state.to_log_returns,
            sliced_state.log_returns, window_size, sampling_period)

          contributions = Portfolio::Risk.contributions_to_volatility(sliced_state, sliced_state.log_returns,
            window_size, sampling_period, marginal_contributions)

          sa = GoogleChart::StackedArea.new
          sa.title = "3 Month Contribution to Volatility (measured monthly)"
          sa.width = 600
          sa.height = 300
          sa.show_legend = true
          sa.encoding = :extended

          x_axis_length = contributions.row(0).size * sampling_period

          colors = random_colors(tickers.size)
          
          contributions.size1.times { |i|
            sa.data "#{tickers[i]}", contributions.row(i).to_a.map {|e| e.abs}, colors[i]
          }

          sa.axis(:left) do |axis|
            axis.alignment = :center
            axis.color = "000000"
            axis.font_size = 16
            axis.range = 0..1
          end

          sa.axis :bottom, :alignment => :center, :color => "000000",
          :font_size => 16, :range => [1, x_axis_length]

          sa.write_to("public/images/portfolio/percent_contribution")

          bc = GoogleChart::BarChart.new
          bc.title = "Basis Point Change in Portfolio Volatility|per 100 Basis Point Change in Holding Weight|(Marginal Contribution to Volatility)"
          bc.width = 400
          bc.height = 400
          bc.show_legend = true
          bc.encoding = :extended

          num_columns = marginal_contributions.size2
          current_marginal_contributions = marginal_contributions.column(num_columns-1).to_a

          bc.axis(:left) do |axis|
            axis.color = "000000"
            axis.font_size = 16
            axis.range = 0..current_marginal_contributions.max*1000
          end

          tickers.size.times { |i|
            bc.data "#{tickers[i]}", [current_marginal_contributions[i]*1000], colors[i]
          }

          bc.write_to("public/images/portfolio/marginal_contributions")

          render :inline => "<%= image_tag(\"portfolio/percent_contribution.png\") %><br/><%= image_tag(\"portfolio/marginal_contributions.png\") %>"
        end
      }
    end
  end

  def return_monte_carlo
      respond_to do |wants|
        wants.js {
          if session[:portfolio].nil?
            render :text => "Please upload portfolio first"
          else
            state = Portfolio::State.new({:tickers => session[:portfolio].tickers,
                :number_of_shares => session[:portfolio].shares})

            offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
            sliced_state = state.slice(offset) # 5 years
            mc_series = sliced_state.return_monte_carlo

            x_series_size = mc_series[:means].size
            x_data = (1..x_series_size).to_a

            means = (mc_series[:means]).to_a
            one_std_above = (mc_series[:means] +
                      mc_series[:upside_standard_deviations]).to_a
            two_std_above = (mc_series[:means] +
                2.0 * mc_series[:upside_standard_deviations]).to_a

            one_std_below = (mc_series[:means] -
                      mc_series[:downside_standard_deviations]).to_a
            two_std_below = (mc_series[:means] -
                2.0 * mc_series[:downside_standard_deviations]).to_a

            Status.info("Generating graphic")
            lc = GoogleChart::LineChart.new
            lc.width = 600
            lc.height = 300
            lc.title = "#{x_series_size} Day Projection (Monte Carlo Simulation with n = 10,000)"

            lc.data "1 Pos. Std. Devs", one_std_above, 'BCED91', "1,6,3"
            lc.data "1 Neg. Std. Devs", one_std_below, 'EEB4B4', "1,6,3"

            lc.data "2 Pos. Std. Devs", two_std_above, '4AC948', "3,6,3"
            lc.data "2 Neg. Std. Devs", two_std_below, 'FF3D0D', "3,6,3"

            lc.data "Mean Return", means, '000000', "3,0,0"

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

            #FIX: This seems like a rather ugly way to do this
            lc.write_to("public/images/portfolio/return_monte_carlo", {:chdlp => 'b'})

            render :inline => "<%= image_tag(\"portfolio/return_monte_carlo.png\") %>"
          end
        }
      end
    end

    def income_monte_carlo
      respond_to do |wants|
        wants.js {
          if session[:portfolio].nil?
            render :text => "Please upload portfolio first"
          else
            state = Portfolio::State.new({:tickers => session[:portfolio].tickers,
                :number_of_shares => session[:portfolio].shares})

            mc_series = state.income_monte_carlo
            initial_income = state.to_income_stream[-1]

            x_data = [0,1,2,3,4]

            means = (mc_series[:means]).to_a
            means.unshift(initial_income)
            
            one_std_above = (mc_series[:means] +
                      mc_series[:upside_standard_deviations]).to_a
            one_std_above.unshift(initial_income)

            two_std_above = (mc_series[:means] +
                2.0 * mc_series[:upside_standard_deviations]).to_a
            two_std_above.unshift(initial_income)
            
            one_std_below = (mc_series[:means] -
                      mc_series[:downside_standard_deviations]).to_a
            one_std_below.unshift(initial_income)
            
            two_std_below = (mc_series[:means] -
                2.0 * mc_series[:downside_standard_deviations]).to_a
            two_std_below.unshift(initial_income)
            
            Status.info("Generating graphic")
            lc = GoogleChart::LineChart.new
            lc.width = 600
            lc.height = 300
            lc.title = "4 Quarter Income Projection (Monte Carlo Simulation with n = 2500)"

            
            lc.data "1 Pos. Std. Devs", one_std_above, 'BCED91', "1,6,3"
            lc.data "1 Neg. Std. Devs", one_std_below, 'EEB4B4', "1,6,3"

            lc.data "2 Neg. Std. Devs", two_std_below, 'FF3D0D', "3,6,3"
            lc.data "2 Pos. Std. Devs", two_std_above, '4AC948', "3,6,3"

            lc.data "Mean Return", means, '000000', "3,0,0"

            lc.encoding = :extended
            lc.show_legend = true

            lc.axis :left, :range => [two_std_below.min.floor,
                                      two_std_above.max.ceil],
            :color => '000000', :font_size => 16, :alignment => :center

            lc.axis :bottom, :range => [x_data[0], x_data[-1]],
              :color => '000000', :font_size => 16, :alignment => :center,
              :labels => [0,1,2,3,4]
           
            #FIX: This seems like a rather ugly way to do this
            lc.write_to("public/images/portfolio/income_monte_carlo", {:chdlp => 'b'})

            render :inline => "<%= image_tag(\"portfolio/income_monte_carlo.png\") %>"
          end
        }
      end
    end

    def sector_allocation
      respond_to do |wants|
        wants.js {
          if session[:portfolio].nil?
            render :text => "Please upload portfolio first"
          else

            tickers = session[:portfolio].tickers

            @chart = GoogleVisualr::PieChart.new
            @chart.add_column('string', 'Sector')
            @chart.add_column('number', 'Holdings')

            sector_hash = Hash.new(0.0)
            available_sectors = ['Basic Materials',
                                 'Conglomerates',
                                 'Consumer Goods',
                                 'Financial',
                                 'Health Care',
                                 'Industrial Goods',
                                 'Services',
                                 'Technology',
                                 'Utilities']


            tickers.each { |ticker|
              company = Company.first(:conditions => {:ticker => ticker.downcase})
              if company.nil?
                company = Company.new({:ticker => ticker.downcase})
                company.save!
              end

              if available_sectors.include?(company.sector)
                sector_hash[company.sector] += 1
              else
                sector_hash['Other'] += 1
              end
            }

            @chart.add_rows(sector_hash.size)
            i = 0
            sector_hash.each { |k, v|
              @chart.set_value(i, 0, k)
              @chart.set_value(i, 1, v)
              i = i + 1
            }

            options = { :width => 600, :height => 400,
              :title => "Sector Allocation (Dow Jones Definition)", :is3D => true }
            options.each_pair { | key, value |
              @chart.send "#{key}=", value
            }

            render :inline => "<%= @chart.render('sector_allocation_results') %>"
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
            tickers = session[:portfolio].tickers
            state = Portfolio::State.new({:tickers => tickers,
                :number_of_shares => session[:portfolio].shares})
            offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
            sliced_state = state.slice(offset) # 5 years

            days = params[:days].to_i
            composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(sliced_state, days)

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
              :title => "#{days} Day Risk Decomposition", :is3D => true }
            options.each_pair { | key, value |
              @chart.send "#{key}=", value
            }

            render :inline => "<%= @chart.render(\"#{days}_day_risk_results\") %>"
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
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          window_size = 125
          sampling_period = 10
          
          factors = Portfolio::Composition::ReturnAnalysis::SECTOR_PROXIES
          return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors, window_size, sampling_period)
          #get a return composition on the sliced-state

          betas = return_values[:betas]
          r_squared = return_values[:r2]

          sa = GoogleChart::StackedArea.new
          sa.title = "Return Decomposition by U.S. Sector (S&P Definition)"
          sa.width = 600
          sa.height = 300
          sa.show_legend = true
          sa.encoding = :extended

          x_axis_length = betas.row(0).size * sampling_period

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
          :font_size => 16, :range => [1, x_axis_length]

          unexplained = r_squared.map { |e| 1.0 - e }
          lc = GoogleChart::StackedArea.new
          lc.width = 600
          lc.height = 150
          lc.title = "R-Squared"

          lc.data "Unexplained", unexplained, random_color
          lc.data "Explained", r_squared, random_color
          
          lc.encoding = :simple
          lc.show_legend = true

          lc.axis :left, :range => [0, 1],
          :color => '000000', :font_size => 16, :alignment => :center

          lc.axis :bottom, :range => [1,x_axis_length],
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
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          window_size = 125
          sampling_period = 10
          
          factors = Portfolio::Composition::ReturnAnalysis::STYLE_PROXIES
          return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors, window_size, sampling_period)
          #get a return composition on the sliced-state

          betas = return_values[:betas]
          r_squared = return_values[:r2]

          points = []
          betas.size2.times { |i|
            location = Portfolio::Composition::ReturnAnalysis::proportions_to_style(betas.column(i))
            points << location.to_a
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

    def rate_return_sensitivity
      respond_to do |wants|
        wants.js {

          tickers = session[:portfolio].tickers
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => session[:portfolio].shares})
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          window_size = 125
          sampling_period = 10

          factors = Portfolio::Composition::ReturnAnalysis::RATE_PROXIES
          return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors, window_size, sampling_period)
          #get a return composition on the sliced-state

          betas = return_values[:betas]

          points = []
          betas.size2.times { |i|
            location = Portfolio::Composition::ReturnAnalysis::proportions_to_rate_and_credit_sensitivity(betas.column(i))
            points << location.to_a
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
          sc.title = "Rate & Credit Sensitivity"
          sc.data "", points, colors.reverse
          sc.encoding = :extended

          #sc.data "Style Points", points, colors
          sc.max_x = 1
          sc.max_y = 1
          sc.min_x = -1
          sc.min_y = -1
          sc.point_sizes Array.new(points.size,1)

          sc.axis(:bottom, :range => -1..1, :labels => ['Short', 'Medium', 'Long'])
          sc.axis(:left, :range => -1..1, :labels => ['Low', 'Medium', 'High'])
          sc.axis(:top, :range => -1..1, :labels => ['Short', 'Medium', 'Long'])
          sc.axis(:right, :range => -1..1, :labels => ['Low', 'Medium', 'High'])

          #FIX: This seems like a rather ugly way to do this
          extras = {
            :chg => "33.33,33.33,1,5"
          }
          sc.write_to("public/images/portfolio/rate_and_credit_return_decomposition", extras)
          render :inline => "<%= image_tag(\"portfolio/rate_and_credit_return_decomposition.png\") %>"
        }
      end
    end

    def asset_return_decomposition
      respond_to do |wants|
        wants.js {

          tickers = session[:portfolio].tickers
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => session[:portfolio].shares})
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          window_size = 125
          sampling_period = 10

          factors = Portfolio::Composition::ReturnAnalysis::ASSET_PROXIES
          return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(sliced_state, factors, window_size, sampling_period)
          #get a return composition on the sliced-state

          betas = return_values[:betas]
          r_squared = return_values[:r2]

          sa = GoogleChart::StackedArea.new
          sa.title = "Return Decomposition by Asset Class"
          sa.width = 600
          sa.height = 300
          sa.show_legend = true
          sa.encoding = :extended

          x_axis_length = betas.row(0).size * sampling_period

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
          :font_size => 16, :range => [1,x_axis_length]

          unexplained = r_squared.map { |e| 1.0 - e }
          lc = GoogleChart::StackedArea.new
          lc.width = 600
          lc.height = 150
          lc.title = "R-Squared"

          lc.data "Unexplained", unexplained, random_color
          lc.data "Explained", r_squared, random_color

          lc.encoding = :simple
          lc.show_legend = true

          lc.axis :left, :range => [0, 1],
          :color => '000000', :font_size => 16, :alignment => :center

          lc.axis :bottom, :range => [1,x_axis_length],
          :color => '000000', :font_size => 16, :alignment => :center

          #FIX: This seems like a rather ugly way to do this
          sa.write_to("public/images/portfolio/asset_return_decomposition", {:chdlp => 'b'})
          lc.write_to("public/images/portfolio/asset_r-squared", {:chdlp => 'b'})

          #send_data(sa.fetch_image, :type => 'image/png',
          #          :file_name => 'Return Composition', :disposition => 'inline')
          render :inline => "<%= image_tag(\"portfolio/asset_return_decomposition.png\") %><br/><%= image_tag(\"portfolio/asset_r-squared.png\") %>"
        }
      end
    end

    def risk_to_return
      respond_to do |wants|
        wants.js {

          tickers = session[:portfolio].tickers.clone
          tickers << 'IWM'

          shares = session[:portfolio].shares.clone
          shares << 1

          state = Portfolio::State.new({:tickers => tickers,
                                        :number_of_shares => shares})
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years
          risks_and_returns = sliced_state.risk_to_return
          
          colors = []
          risks_and_returns.size.times { |i|
            colors << random_color
          }

          risks_and_returns.map! { |e| [e[0]*100, e[1]*100] }
          Rails.logger.info(risks_and_returns)

          tickers << "Portfolio"
          # Scatter Plot

          @chart = GoogleVisualr::ScatterChart.new
          @chart.add_column('number', 'Risk')
          #@chart.add_column('string', 'Ticker')

          risks_and_returns.size.times { |i|
            @chart.add_column('number', "#{tickers[i]}")
          }
          @chart.add_rows(risks_and_returns.size)
          
          risks_and_returns.size.times { |i|
            risk, ret = risks_and_returns[i]
            @chart.set_value( i, 0, risk  )
            #@chart.set_value( i, 1, tickers[i])
            @chart.set_value( i, i+1, ret )
          }

          options = { :width => 600,
                      :height => 400,
                      :titleX => 'Risk',
                      :titleY => 'Return',
                      :legend => 'bottom`',
                      :pointSize => 5,
                      :title => 'Annualized Risk vs Return'
                    }
          options.each_pair do | key, value |
            @chart.send "#{key}=", value
          end

          render :inline => "<%= @chart.render('risk_vs_return_results') %>"
        }
      end
    end

    def up_down_capture
      respond_to do |wants|
        wants.js {

          tickers = session[:portfolio].tickers
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => session[:portfolio].shares})
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          points = Portfolio::Risk::upside_downside_capture(sliced_state, ["IWM"], 60, 20) << [1.0,1.0]

          total_points = points.size - 2
          
          max_x = points.map { |e| e[0] }.flatten.max
          max_y = points.map { |e| e[1] }.flatten.max

          min_x = points.map { |e| e[0] }.flatten.min
          min_y = points.map { |e| e[1] }.flatten.min

          # add line points (edges of 
          points << [[min_x, min_y].max, [min_x, min_y].max] <<
                    [[max_y, max_x].min, [max_y, max_x].min]

          
          colors = []
          total_points.times { |i|
            colors << greyscale_to_rgb(i / total_points.to_f)
          }
          colors.unshift("FF0000") #current time is red
          colors.unshift("00FF00") #portfolio is green

          colors.unshift("000000") #mask our final points
          colors.unshift("000000")

          # Scatter Plot
          sc = GoogleChart::ScatterPlot.new
          sc.width = 500
          sc.height = 500
          sc.title = "3-Month Up / Down Capture Analysis against Russell 2000 (measured monthly)"
          sc.data "", points, colors.reverse
          sc.encoding = :extended

          #sc.data "Style Points", points, colors
          
          sc.max_x = max_x
          sc.max_y = max_y

          sc.min_x = min_x
          sc.min_y = min_y

          sizes = Array.new(points.size,1)
          sizes[-3] = 0
          sizes[-2] = 0 #mask our final points
          sizes[-1] = 0
          sc.point_sizes sizes

          sc.axis(:bottom, :range => min_x..max_x)
          sc.axis(:left, :range => min_y..max_y)

          Rails.logger.info(points)
          #FIX: This seems like a rather ugly way to do this
          extras = {
            :chm => "D,C6DEFF,1,#{points.size-2}:#{points.size-1}:,1,-1|s,00FF00,0,#{points.size-3},16"
          }

          sc.write_to("public/images/portfolio/up_down_capture", extras)

          #send_data(sa.fetch_image, :type => 'image/png',
          #          :file_name => 'Return Composition', :disposition => 'inline')
          render :inline => "<%= image_tag(\"portfolio/up_down_capture.png\") %>"
        }
      end
    end
  end
