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
  end

  def correlation_analysis
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

          s = "<table width=#{tickers.size*10} height=#{tickers.size*10} border=0>"
          s += "<tr><td></td>"
          tickers.each { |t|
            s += "<td><b>#{t.upcase}</b></td>"
          }
          s += "<tr>"

          correlation_matrix = state.sample_correlation_matrix

          # ipc = sum(i) sum(j) x(i)x(j)p(i,j) i != j
          ipc = state.weights * correlation_matrix * state.weights.col
          # now we have to subtract the correlation of 1 (diagonals)
          # subtract the sum of the weights squared
          ipc = ipc - state.weights * state.weights.col

          #concentration coefficient
          cc = 1.0 / (state.weights * state.weights.col)

          tickers.size.times { |i|
            r = correlation_matrix.row(i)
            s += "<tr>"
            s += "<td><b>#{tickers[i].upcase}</b></td>"
            r.size.times { |j|
              clamped = (r[j] * 100).to_i / 100.0

              # generate the appropriate color
              color = hsv_to_rgb_string(0, clamped.abs**2, 1.0)

              s += "<td bgcolor=\"#{color}\">#{clamped}</td>"
            }
            s += "</tr>"
          }

          s += "</table>"
          s += "<br/><b>IPC:</b> #{ipc}"
          s += "<br/><b>Concentration Coefficient:</b> #{cc}"
          render :inline => s
        end
      }
    end
  end

  def volatility_analysis
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

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
          bc.encoding = :text

          num_columns = marginal_contributions.size2
          current_marginal_contributions = marginal_contributions.column(num_columns-1).to_a

          bc.axis(:left) do |axis|
            axis.color = "000000"
            axis.font_size = 16
            axis.range = 0..current_marginal_contributions.max*1000
          end

          bc.min = 0
          bc.max = current_marginal_contributions.max*1000

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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
            tickers = holdings.map { |e| e[0] }
            shares = holdings.map { |e| e[1] }
            state = Portfolio::State.new({:tickers => tickers,
                :number_of_shares => shares})

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
            lc.title = "#{x_series_size} Day Projection|(Monte Carlo Simulation with n = 10,000)"

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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
            tickers = holdings.map { |e| e[0] }
            shares = holdings.map { |e| e[1] }
            state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

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
            lc.title = "4 Quarter Income Projection|(Monte Carlo Simulation with n = 2500)"

            
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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
            tickers = holdings.map { |e| e[0] }
            shares = holdings.map { |e| e[1] }
            state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

            offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
            sliced_state = state.slice(offset) # 5 years

            days = params[:days].to_i
            composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(sliced_state, days)

            portfolio_var = composite_risk[:portfolio_var]
            portfolio_cvar = composite_risk[:portfolio_cvar]
            individual_vars = composite_risk[:individual_vars]
            individual_cvars = composite_risk[:individual_cvars]
            marginal_vars = composite_risk[:marginal_vars]
            component_var_proportion = composite_risk[:proportion_of_var]

            colors = random_colors(tickers.size)

            bc = GoogleChart::BarChart.new
            bc.title = "Individual Value-at-Risk|(Measured in Dollars)"
            bc.width = 500
            bc.height = 350
            bc.show_legend = true
            bc.encoding = :text

            bc.min = 0
            bc.max = individual_vars.max

            bc.axis(:left) do |axis|
              axis.color = "000000"
              axis.font_size = 16
              axis.range = 0..individual_vars.max
            end

            tickers.size.times { |i|
              bc.data "#{tickers[i]}", [individual_vars[i]], colors[i]
            }

            bc.write_to("public/images/portfolio/individual_vars", {:chdlp => 'b'})

            bc = GoogleChart::BarChart.new
            bc.title = "Individual Conditional Value-at-Risk|(Measured in Dollars)"
            bc.width = 500
            bc.height = 350
            bc.show_legend = true
            bc.encoding = :text

            bc.min = 0
            bc.max = individual_cvars.max

            bc.axis(:left) do |axis|
              axis.color = "000000"
              axis.font_size = 16
              axis.range = 0..individual_cvars.max
            end

            tickers.size.times { |i|
              bc.data "#{tickers[i]}", [individual_cvars[i]], colors[i]
            }

            bc.write_to("public/images/portfolio/individual_cvars", {:chdlp => 'b'})

            bc = GoogleChart::BarChart.new
            bc.title = "Marginal Value-at-Risk (in $)"
            bc.width = 500
            bc.height = 350
            bc.show_legend = true
            bc.encoding = :text

            bc.min = 0
            bc.max = marginal_vars.max

            bc.axis(:left) do |axis|
              axis.color = "000000"
              axis.font_size = 16
              axis.range = 0..marginal_vars.max
            end

            tickers.size.times { |i|
              bc.data "#{tickers[i]}", [marginal_vars[i]], colors[i]
            }

            bc.write_to("public/images/portfolio/marginal_vars", {:chdlp => 'b'})

            render :inline => "<%= \"Portfolio VaR: #{portfolio_var}\" %><br/>
                               <%= \"Portfolio CVaR: #{portfolio_cvar}\" %><br/>
                            <%= image_tag(\"portfolio/individual_vars.png\") %><br/>
                            <%= image_tag(\"portfolio/individual_cvars.png\") %><br/>
                            <%= image_tag(\"portfolio/marginal_vars.png\") %><br/>"
          end
        }
      end
    end

    def sector_return_decomposition
      respond_to do |wants|
        wants.js {

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
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
          sc.title = "Term & Credit Sensitivity"
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
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
          
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          tickers << 'IWM'
          shares = holdings.map { |e| e[1] }
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          points = Portfolio::Risk::upside_downside_capture(sliced_state, 
            {:tikers => ["IWM"], :number_of_shares => [1]}, 60, 20) << [1.0,1.0]
  

          total_points = points.size - 2
          
          max_x = points.map { |e| e[0] }.flatten.max
          max_y = points.map { |e| e[1] }.flatten.max

          min_x = points.map { |e| e[0] }.flatten.min
          min_y = points.map { |e| e[1] }.flatten.min

          # add line points (edges of bounding box)
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
          sc.title = "3-Month Up / Down Capture Analysis|against Russell 2000 (measured monthly)"
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

    def eigen_value_decomposition
      respond_to do |wants|
        wants.js {
          if session[:portfolio].nil?
            render :text => "Please upload portfolio first"
          else
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort { |a,b| a[0] <=> b[0] }
            tickers = holdings.map { |e| e[0] }
            shares = holdings.map { |e| e[1] }

            # include cash as a possibility
            unless tickers.map { |e| e.downcase }.include?('bil')
              tickers << 'BIL'
              shares << 1
            end

            state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
            offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
            portfolio_state = state.slice(offset) # ~5 years

            eigen_values, percent_variance, eigen_vectors =
                  Portfolio::Composition::ReturnAnalysis::pca(portfolio_state)

            colors = random_colors(eigen_values.size)

            lc = GoogleChart::LineChart.new
            lc.width = 600
            lc.height = 300


            #identify which dimension to associate a holding with
            num_dimensions = eigen_vectors.size2
            identified_dimension = Array.new(tickers.size)
            current_max = Array.new(tickers.size, 0.0)
            num_dimensions.times { |i|
              if percent_variance[i] > 0.025
                vector = eigen_vectors.column(i)
                minimum = vector.min
                maximum = vector.max
                mean = vector.mean

                vector.size.times { |j|
                  dimension_score =  [vector[j] - mean,  vector[j]].max *
                                                              percent_variance[i]

                  if current_max[j] < dimension_score
                    current_max[j] = dimension_score
                    identified_dimension[j] = i
                  end
                }
              end
            }

            unique_dimensions = identified_dimension.uniq.sort
            
            total_variance = 0
            unique_dimensions.sort.each { |i|
              lc.data "Dimension #{i+1}", eigen_vectors.column(i).to_a, colors[i]
              total_variance = total_variance + percent_variance[i]
            }
            
            total_variance = (total_variance * 10000).to_i / 10000.0
            lc.title = "Principal Component Analysis|(#{total_variance*100}% of variance)"

            lc.encoding = :extended
            lc.show_legend = true

            minimum = eigen_vectors.to_a.flatten.min.floor
            maximum = eigen_vectors.to_a.flatten.max.ceil

            lc.axis :left, :range => [minimum, maximum],
              :color => '000000', :font_size => 16, :alignment => :center

            lc.axis :bottom, :range => [1, tickers.size],
              :color => '000000', :font_size => 8, :alignment => :center,
              :labels => tickers

            extras = {
              :chg => "10,10,1,5"
            }

            lc.write_to("public/images/portfolio/eigen_vector_decomp", {:chdlp => 'b'})

            bc = GoogleChart::BarChart.new
            bc.title = "Contribution to Variance"
            bc.width = 500
            bc.height = 350
            bc.show_legend = true
            bc.encoding = :text

            used_variance = []
            unique_dimensions.each { |i|
              used_variance << percent_variance[i]*100
              bc.data "Dimension #{i+1}", [percent_variance[i]*100], colors[i]
            }

            bc.min = 0
            bc.max = used_variance.max

            bc.axis(:left) do |axis|
              axis.color = "000000"
              axis.font_size = 16
              axis.range = 0..used_variance.max
            end


            bc.write_to("public/images/portfolio/eigen_value_decomp", {:chdlp => 'b'})

            s = "<%= image_tag(\"portfolio/eigen_vector_decomp.png\") %><br/><%= image_tag(\"portfolio/eigen_value_decomp.png\") %>"
            s += "<br/>"

            groups = tickers.zip(identified_dimension).group_by { |e| e[1] }

            groups.keys.sort.each { |group_id|
              group = groups[group_id]
              sorted_group = group.sort { |a,b| a[0] <=> b[0] }
              s += "<b>Group #{group_id+1}</b>: "
              sorted_group.each { |holding|
                s += "#{holding[0]} "
              }
              s += "<br/>"
            }

            # now that we have reduced dimensionality, find the points in n-space
            # based on their correlation
            n_holdings = tickers.size
            n_dimensions = [groups.size, 7].min #max out at 7 dimensions

            number_of_dimensions = n_holdings * n_dimensions
            feature_limits = []
            number_of_dimensions.times { |i|
              feature_limits << [-1.0, 1.0]
            }

            # Target error of 5% per entry
            absolute_tolerance = portfolio_state.sample_correlation_matrix.to_v.map { |e| e.abs }.sum * 0.05

            fitness_function = Proc.new { |fly_position|

              cosine_matrix = GSL::Matrix.alloc(n_holdings, n_holdings)
              positions = GSL::Matrix.alloc(n_holdings, n_dimensions)
              tickers.size.times { |i|
                v = fly_position.get(i*n_dimensions, n_dimensions).normalize
                positions.set_row(i, v)
              }

              # now that the positions are set, find the cosine matrix
              tickers.size.times { |i|
                a = positions.row(i)
                cosine_matrix[i,i] = 1.0
                (i+1).upto(tickers.size-1) { |j|
                  b = positions.row(j)
                  cosine_matrix[i,j] = a * b.transpose
                  cosine_matrix[j,i] = cosine_matrix[i,j]
                }
              }

              (portfolio_state.sample_correlation_matrix - cosine_matrix).to_v.map { |e| e**2 }.sum
            }

            fitness, features = Optimization::ParticleSwarmOptimization::optimize_over(
                    Math.sqrt(number_of_dimensions).floor * 20,
                    number_of_dimensions, feature_limits,
                    2, 2, 2, 0.1, 0.05, fitness_function,
                    {:absolute_tolerance => absolute_tolerance})

            positions = GSL::Matrix.alloc(n_holdings, n_dimensions)
              tickers.size.times { |i|
                v = features.get(i*n_dimensions, n_dimensions).normalize
                positions.set_row(i, v)
            }

            vector_scores = GSL::Vector.alloc(tickers.size)
            vector_scores.map! { |e| rand * 25 }
            
            data_points = []
            (positions.size1-1).times { |i|
              data_points << (positions.row(i) * vector_scores[i]).to_a
            }
            data_points << GSL::Vector.alloc(n_dimensions).set_all(0.0).to_a

            indices = Convex::qhull(data_points.size, n_dimensions, data_points).uniq

            s += "<br/><b>Include:</b><br/> "
            indices.each { |index|
              s += "#{tickers[index]} "
            }

            select_tickers = indices.map { |i| tickers[i] }
            select_shares = indices.map { |i| shares[i] }
            select_scores = indices.map { |i| vector_scores[i] }

            select_state = Portfolio::State.new({:tickers => select_tickers,
              :number_of_shares => select_shares})

            offset = (select_state.dates.size - 1250) < 0 ? 0 : (select_state.dates.size - 1250)
            select_portfolio_state = select_state.slice(offset) # ~5 years

            feature_limits = []
            select_tickers.size.times { |i|
              feature_limits << [0, 1]
            }

            fitness_function = Proc.new { |weights|
              # get the weights as a proportion to the whole
              pweights = weights / weights.sum

              ipc = (pweights * select_portfolio_state.sample_correlation_matrix * pweights.col - pweights * pweights.col)

              pscore = 0
              pweights.size.times { |i|
                pscore = pscore + pweights[i] * select_scores[i]
              }

              # since we want to minimize ipc and maximize pscore,
              # but we are running a minimization algorithm, we put pscore on the
              # bottom and ipc on the top

              #since ipc is in [-1, 1], we have to add 1 to it, so that
              # a score of -1 remains stronger than a -0.0001 when divided
              # by identical pscores.
              (ipc + 1.0) / pscore
            }

            fitness, features = Optimization::ParticleSwarmOptimization::optimize_over(
                    10*select_tickers.size,
                    select_tickers.size, feature_limits,
                    1, 1, 1, 0.1, 0.05, fitness_function,
                    {:maximum_stuck => 500})

            features = features / features.sum
            s += "<br/><b>IPC:</b> #{features * select_portfolio_state.sample_correlation_matrix * features.col - features * features.col}<br/>"
            s += "<b>CC:</b> #{1.0 / (features * features.col)}<br/>"

            s += "<b>Weights</b><br/>"
            select_tickers.size.times { |i|
              s += "#{select_tickers[i]}: #{features[i]}<br/>"
            }
            
            render :inline => s
          end
        }
      end
    end
  end