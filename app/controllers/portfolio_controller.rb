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
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

          font_size = [1, (25 / tickers.size).floor].max

          inline_renderable = "<table width=#{tickers.size*10} height=#{tickers.size*10} border=0>"
          inline_renderable += "<tr><td></td>"
          tickers.each { |t|
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t.upcase}</b></font></td>"
          }
          inline_renderable += "<tr>"

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
            inline_renderable += "<tr>"
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{tickers[i].upcase}</b></font></td>"
            r.size.times { |j|
              clamped = (r[j] * 100).to_i / 100.0

              # generate the appropriate color
              color = hsv_to_rgb_string(0, clamped.abs**2, 1.0)

              inline_renderable += "<td bgcolor=\"#{color}\"><font size=\"#{font_size}\">#{clamped}</font></td>"
            }
            inline_renderable += "</tr>"
          }

          ipc_pct = (1.0 - ipc)/2.0
          #weird fucking hack to get the http get to go through ... requires a newline?!
          image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@a,000000,1,#{ipc_pct}:.5,7,0
            ")
          File.open("public/images/portfolio/heat_chart.png", "w") { |f|
            Rails.logger.info(image)
            f << image
          }

          inline_renderable += "</table>"
          inline_renderable += "<br/><b>IPC:</b> #{100*ipc_pct}%<br/>"
          inline_renderable += "<%= image_tag 'portfolio/heat_chart.png' %><br/>"
          inline_renderable += "<br/><b>Concentration Coefficient:</b> #{cc}"
          render :inline => inline_renderable
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
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})

          window_size = 120
          sampling_period = 20
          
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # 5 years

          marginal_contributions = Portfolio::Risk.marginal_contribution_to_volatility(sliced_state.to_log_returns,
            sliced_state.log_returns, window_size, sampling_period)

          contributions = Portfolio::Risk.contributions_to_volatility(sliced_state, sliced_state.log_returns,
            window_size, sampling_period, marginal_contributions)

          sa = GoogleChart::StackedArea.new
          sa.title = "6 Month Contribution to Volatility (measured monthly)"
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

          inline_renderable = "<%= image_tag(\"portfolio/percent_contribution.png\") %><br/><br/>"
          num_columns = marginal_contributions.size2
          current_marginal_contributions = marginal_contributions.column(num_columns-1).to_a

          tickers.each_with_index { |ticker, i|
            inline_renderable += "<b>#{ticker}</b>: #{current_marginal_contributions[i]*1000}<br/>"
          }

          render :inline => inline_renderable
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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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
            lc.title = "4 Quarter Income Projection|(Monte Carlo Simulation with n = 10,000)"

            
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

            sector_hash = Hash.new(0.0)

            available_sectors = ['Basic Materials',
                                 'Conglomerates',
                                 'Consumer Goods',
                                 'Financial',
                                 'Healthcare',
                                 'Industrial Goods',
                                 'Services',
                                 'Technology',
                                 'Utilities']

            colors = random_colors(available_sectors.size)

            tickers.each { |ticker|
              company = Company.new({:ticker => ticker.downcase})

              if available_sectors.include?(company.sector)
                sector_hash[company.sector] += 1
              else
                sector_hash['Other'] += 1
              end
            }

            i = 0
            pc = GoogleChart::PieChart.new
            sector_hash.keys.sort.each { |k|
              clamped = ((sector_hash[k] / tickers.size.to_f) * 10000).to_i / 10000.0
              pc.data "#{k} (#{sector_hash[k].to_i} at #{clamped*100}%)", sector_hash[k], colors[i]
              i = i + 1
            }
            pc.height = 300
            pc.width = 600
            pc.title = "Sector Allocation (Dow Jones Definition)"
            #pc.is_3d = true

            pc.write_to("public/images/portfolio/sector_allocation", {:chdlp => 'b'})

            render :inline => "<%= image_tag(\"portfolio/sector_allocation.png\") %>"
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
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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
            component_vars = composite_risk[:component_vars]

            inline_renderable = "<b>Portfolio VaR</b>: #{portfolio_var}<br/>"
            inline_renderable += "<b>Portfolio CVaR</b>: #{portfolio_cvar}<br/>"

            inline_renderable += "<h3>Individual VaRs</h3><br/>"
            tickers.each_with_index { |ticker, i|
              inline_renderable += "<b>#{ticker}</b>: #{individual_vars[i]}<br/>"
            }

            inline_renderable += "<br/><h3>Conditional VaRs</h3><br/>"
            tickers.each_with_index { |ticker, i|
              inline_renderable += "<b>#{ticker}</b>: #{individual_cvars[i]}<br/>"
            }

            inline_renderable += "<br/><h3>Component VaRs</h3><br/>"
            tickers.each_with_index { |ticker, i|
              inline_renderable += "<b>#{ticker}</b>: #{component_vars[i]} -- #{component_vars[i] / portfolio_var}<br/>"
            }

            inline_renderable += "<br/><h3>Marginal VaRs</h3><br/>"
            tickers.each_with_index { |ticker, i|
              inline_renderable += "<b>#{ticker}</b>: #{marginal_vars[i]}<br/>"
            }

            render :inline => inline_renderable
          end
        }
      end
    end

    def sector_return_decomposition
      respond_to do |wants|
        wants.js {

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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

          colors = random_colors(factors.keys.size)

          factor_names = factors.keys.sort
          i = 0
          factor_names.each { |fn|
            sa.data "#{fn}", betas.row(factors.keys.index(fn)).to_a, colors[i]
            i = i + 1
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

          colors = random_colors(2)
          lc.data "Unexplained", unexplained, colors[0]
          lc.data "Explained", r_squared, colors[1]
          
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          window_size = 120
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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

          colors = random_colors(factors.keys.size)
          factor_names = factors.keys
          betas.size1.times { |i|
            sa.data "#{factor_names[i]}", betas.row(i).to_a, colors[i]
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

          colors = random_colors(2)
          lc.data "Unexplained", unexplained, colors[0]
          lc.data "Explained", r_squared, colors[1]

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
          
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
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

          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # ~5 years

          points = Portfolio::Risk::upside_downside_capture(sliced_state,
            {:tickers => ["IWM"], :number_of_shares => [1]}, 120, 5) << [1.0, 1.0]

          total_points = points.size - 2
          
          max_x = points.map { |e| e[0] }.flatten.max
          max_y = points.map { |e| e[1] }.flatten.max

          min_x = points.map { |e| e[0] }.flatten.min
          min_y = points.map { |e| e[1] }.flatten.min

          mean_x = points[0...total_points].inject(0.0) { |s, e| s + e[0] } / total_points.to_f
          var_x = points[0...total_points].inject(0.0) { |s, e| s + (e[0] - mean_x)**2 } / total_points.to_f

          mean_y = points[0...total_points].inject(0.0) { |s, e| s + e[1] } / total_points.to_f
          var_y = points[0...total_points].inject(0.0) { |s, e| s + (e[1] - mean_y)**2 } / total_points.to_f

          z = 1.96
          left = mean_x - z*Math.sqrt(var_x)
          right = mean_x + z*Math.sqrt(var_x)
          top = mean_y + z*Math.sqrt(var_y)
          bottom = mean_y - z*Math.sqrt(var_y)
          
          max_x = [max_x, right].max
          min_x = [min_x, left].min
          max_y = [max_y, top].max
          min_y = [min_y, bottom].min

          # add line points (edges of bounding box)
          points << [[min_x, min_y].max, [min_x, min_y].max] <<
                    [[max_y, max_x].min, [max_y, max_x].min]

          points <<  [left, top] <<  #top left
                     [right,top] <<  #top right
                     [right, bottom] <<  #bottom right
                     [left, bottom] <<  #bottom left
                     [left, top]     #top left
          
          colors = []
          total_points.times { |i|
            colors << greyscale_to_rgb(i / total_points.to_f)
          }
          colors.unshift("FF0000") #current time is red
          colors.unshift("00FF00") #portfolio is green

          7.times {
            colors.unshift("000000") #mask our final points
          }

          # Scatter Plot
          sc = GoogleChart::ScatterPlot.new
          sc.width = 500
          sc.height = 500
          sc.title = "6-Month Up / Down Capture Analysis|against Russell 2000 (measured weekly)"
          sc.data "", points, colors.reverse
          sc.encoding = :extended

          #sc.data "Style Points", points, colors
          
          sc.max_x = max_x
          sc.max_y = max_y

          sc.min_x = min_x
          sc.min_y = min_y

          sizes = Array.new(points.size,1)
          # -7 through -1 should be zeros
          7.times { |i|
            sizes[-(i+1)] = 0
          }
          sc.point_sizes sizes

          sc.axis(:bottom, :range => min_x..max_x)
          sc.axis(:left, :range => min_y..max_y)

          #FIX: This seems like a rather ugly way to do this

          # we go from -7 to -1
          # -7 and -6 should be connected
          # -5 through -1 should be connected
          chm = "D,3366FF,1,#{points.size-7}:#{points.size-6}:,1,-1|"
          4.times { |i|
            chm += "D,33FF66,1,#{points.size-(5-i)}:#{points.size-(4-i)}:,1,-1|"
          }
          chm += "s,00FF00,0,#{points.size-8},16"
          extras = {
            :chm => chm
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
            inline_renderable = ""
            
            holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
            tickers = holdings.map { |e| e[0] }
            shares = holdings.map { |e| e[1] }

            state = Portfolio::State.new({:tickers => tickers,
              :number_of_shares => shares})
          
            offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
            portfolio_state = state.slice(offset) # ~5 years

            eigen_values, percent_variance, eigen_vectors =
                  Portfolio::Composition::ReturnAnalysis::pca(portfolio_state)

            #identify which dimension to associate a holding with
            identified_dimension = Array.new(tickers.size)
            sqrt_variance = percent_variance.map { |e| Math.sqrt(e) }
            tickers.size.times { |i|
              # take the eigen_vector matrix
              # and for each column in our correlation matrix,
              # solve for our betas.  find the max beta, and use that as
              # our identified dimension
              c, cov, chisq, status = GSL::MultiFit::linear(eigen_vectors.transpose, portfolio_state.sample_correlation_matrix.column(i))
              identified_dimension[i] = (c * sqrt_variance).map {|e| e.abs }.sort_index[-1]
            }

            unique_dimensions = identified_dimension.uniq.sort

            clusters = Cluster.hierarchical(portfolio_state.sample_correlation_matrix, unique_dimensions.size)
            clustered_tickers = clusters.map { |e| e.map { |i| tickers[i] }}

            clustered_tickers.each_with_index { |cluster, i|
              inline_renderable += "<b>Cluster #{i+1}</b>: "
              inline_renderable += cluster.join(" ")
              inline_renderable += "<br/>"
            }
            inline_renderable += "<br/>"
 
=begin
            # now that we have reduced dimensionality, find the points in n-space
            # based on their correlation
            n_holdings = tickers.size
            n_dimensions = [[clustered_tickers.size, 3].max, 7].min #min 3, max 7 dimensions

            number_of_dimensions = n_holdings * n_dimensions
            feature_limits = []
            number_of_dimensions.times { |i|
              feature_limits << [-1.0, 1.0]
            }

            fitness, features = Optimization::ParticleSwarmOptimization::optimize_over(
                    [Math.sqrt(number_of_dimensions).floor * 20, 500].min,
                    number_of_dimensions, feature_limits,
                    2, 2, 2, 0.1, 0.05) { |fly_position|

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

            positions = GSL::Matrix.alloc(n_holdings, n_dimensions)
              tickers.size.times { |i|
                v = features.get(i*n_dimensions, n_dimensions).normalize
                positions.set_row(i, v)
            }

            vector_scores = GSL::Vector.alloc(tickers.size)
            #vector_scores.set_all(1.0)
            vector_scores.map! { |e| rand }
            
            data_points = []
            (positions.size1).times { |i|
              data_points << (positions.row(i) * vector_scores[i])
            }

            hull_summary = Convex::qhull(data_points.size, 
                                         n_dimensions,
                                         data_points)
            indices = hull_summary[:indices].uniq
            faces = hull_summary[:faces]

            inline_renderable += "<br/><b>Include:</b><br/> "
            indices.each { |index|
              inline_renderable += "#{tickers[index]} "
            }
            inline_renderable += "<br/>"

            center_of_gravity = GSL::Vector.alloc(n_dimensions).set_all(0.0)
            data_points.each { |dp|
              center_of_gravity = center_of_gravity + dp
            }
            center_of_gravity = center_of_gravity / data_points.size

            total_inner_surface_area = 0
            contributed_inner_surface_area = Hash.new(0.0)
            faces.each { |face|
              #given pairs of two points in the face,
              #find the area of the triangle with third point
              #center of gravity
              face.size.times { |i|
                j = (i + 1) == face.size ? -1 : i+1

                p1 = face[i]
                p2 = face[j]

                a = (data_points[p1] - data_points[p2]).nrm2
                b = (data_points[p1] - center_of_gravity).nrm2
                c = (data_points[p2] - center_of_gravity).nrm2

                # area of triangle given three sides
                s = (a+b+c)/2.0
                area = Math.sqrt(s*(s-a)*(s-b)*(s-c))

                total_inner_surface_area += area
                contributed_inner_surface_area[p1] += area/2.0
                contributed_inner_surface_area[p2] += area/2.0
              }
            }

            weights = GSL::Vector[*indices.map { |i|
                contributed_inner_surface_area[i] /
                   total_inner_surface_area }]
            
            select_tickers = indices.map { |e| tickers[e] }
            select_shares = indices.map { |e| shares[e] }

            select_state = Portfolio::State.new({:tickers => select_tickers,
              :number_of_shares => select_shares})

            offset = (select_state.dates.size - 1250) < 0 ? 0 : (select_state.dates.size - 1250)
            select_portfolio_state = select_state.slice(offset) # ~5 years

            ipc = weights * select_portfolio_state.sample_correlation_matrix * weights.col
            ipc = ipc - weights * weights.col

            select_tickers.zip(weights.to_a) { |t,w|
              inline_renderable += "#{t}: #{w}<br/>"
            }
            inline_renderable += "<br/><b>IPC:</b> #{100*(1.0 - ipc)/2.0}%<br/>"
=end
            render :inline => inline_renderable
          end
        }
      end
    end
  end