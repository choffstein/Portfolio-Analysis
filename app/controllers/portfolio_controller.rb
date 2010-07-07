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

  def run_report
    if session[:portfolio].nil?
      render :text => "Please upload portfolio first"
    else
      holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
      tickers = holdings.map { |e| e[0] }
      shares = holdings.map { |e| e[1] }
      state = Portfolio::State.new({:tickers => tickers,
          :number_of_shares => shares})

      offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
      state = state.slice(offset) # 5 years

      # color_coded_correlation, ipc, filename
      correlation_analysis(sliced_state)

      # expected_volatility, file_name, marginal_contributions
      volatility_analysis(state)

      # file_name
      return_monte_carlo(state)
          
      # file_name
      income_monte_carlo(state)

      # file_names
      sector_allocation_analysis(state)

      # portfolio_var, portfolio_cvar
      # holding_vars
      #     individual_var
      #     individual_cvar
      #     component_var
      #     proportion_var
      #     marginal_var
      risk_decomposition_analysis(state)

      # file_names
      sector_return_decomposition(state)

      # file_name
      style_return_decomposition(state)

      # file_name
      rate_return_sensitivity(state)

      # file_names
      asset_return_decomposition(state)

      # file_name
      up_down_capture(state)

      # identified_clusters, num_unique_clusters
      dimensionality_analysis(state)
    end
  end

  def render_correlation_analysis
    respond_to do |wants|
      wants.js {
        if session[:portfolio].nil?
          render :text => "Please upload portfolio first"
        else
          holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
          tickers = holdings.map { |e| e[0] }
          shares = holdings.map { |e| e[1] }
          
          state = Portfolio::State.new({:tickers => tickers, :number_of_shares => shares})

          font_size = [1, (25 / tickers.size).floor].max

          inline_renderable = "<table width=#{tickers.size*10} height=#{tickers.size*10} border=0>"
          inline_renderable += "<tr><td></td>"
          tickers.each { |t|
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t.upcase}</b></font></td>"
          }
          inline_renderable += "<tr>"

          # color_coded_correlation, ipc, filename
          results = correlation_analysis(state)

          tickers.each { |t1|
            inline_renderable += "<tr>"
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t1.upcase}</b></font></td>"
            tickers.each { |t2|
              color = results[:color_coded_correlation][t1.downcase][t2.downcase][:color]
              correlation = results[:color_coded_correlation][t1.downcase][t2.downcase][:correlation]
              clamped = correlation * 100 / 100
              inline_renderable += "<td bgcolor=\"#{color}\"><font size=\"#{font_size}\">#{clamped}</font></td>"
            }
            inline_renderable += "</tr>"
          }

          ipc_pct = results[:ipc]

          inline_renderable += "</table>"
          inline_renderable += "<br/><b>IPC:</b> #{100*ipc_pct}%<br/>"
          inline_renderable += "<%= image_tag '#{results[:file_name]}' %><br/>"
          render :inline => inline_renderable
        end
      }
    end
  end

  def render_volatility_analysis
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

          results = volatility_analysis(sliced_state)

            
          inline_renderable = "Expected Volatility: #{results[:expected_volatility]}<br/>"
          inline_renderable += "<%= image_tag '#{results[:file_name]}' %><br/><br/>"

          marginal_contributions = results[:marginal_contributions]
          num_columns = marginal_contributions.size2
          current_marginal_contributions = marginal_contributions.column(num_columns-1).to_a

          inline_renderable += "<h3>Marginal Contribution to Volatility</h3>"
          tickers.each_with_index { |ticker, i|
            inline_renderable += "<b>#{ticker}</b>: #{current_marginal_contributions[i]*1000}<br/>"
          }

          render :inline => inline_renderable
        end
      }
    end
  end

  def render_expected_return_monte_carlo
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

          results = expected_return_monte_carlo(sliced_state)
          render :inline => "<%= image_tag '#{results[:file_name]}' %>"
        end
      }
    end
  end

  def render_income_monte_carlo
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

          results = income_monte_carlo(state)
          render :inline => "<%= image_tag '#{results[:file_name]}' %>"
        end
      }
    end
  end
    
  def render_sector_allocation
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
            
          results = sector_allocation_analysis(state)
          render :inline => "<%= image_tag '#{results[:file_name]}' %>"
        end
      }
    end
  end

  def render_risk_decomposition
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

          results = risk_decomposition_analysis(sliced_state)
            

          inline_renderable = "<b>Portfolio VaR</b>: #{results[:portfolio_var]}<br/>"
          inline_renderable += "<b>Portfolio CVaR</b>: #{results[:portfolio_cvar]}<br/>"

          inline_renderable += "<h3>Individual VaRs</h3><br/>"
          tickers.each { |ticker|
            inline_renderable += "<b>#{ticker}</b>: #{results[:holding_vars][ticker][:individual_var]}<br/>"
          }

          inline_renderable += "<br/><h3>Conditional VaRs</h3><br/>"
          tickers.each { |ticker|
            inline_renderable += "<b>#{ticker}</b>: #{results[:holding_vars][ticker][:individual_cvar]}<br/>"
          }

          inline_renderable += "<br/><h3>Component VaRs</h3><br/>"
          tickers.each { |ticker|
            inline_renderable += "<b>#{ticker}</b>: #{results[:holding_vars][ticker][:component_var]} -- #{results[:holding_vars][ticker][:proportion_var]}<br/>"
          }

          inline_renderable += "<br/><h3>Marginal VaRs</h3><br/>"
          tickers.each { |ticker|
            inline_renderable += "<b>#{ticker}</b>: #{results[:holding_vars][ticker][:marginal_var]}<br/>"
          }

          render :inline => inline_renderable
        end
      }
    end
  end

  def render_sector_return_decomposition
    respond_to do |wants|
      wants.js {

        holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
        tickers = holdings.map { |e| e[0] }
        shares = holdings.map { |e| e[1] }
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => shares})
          
        offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
        sliced_state = state.slice(offset) # ~5 years

        results = sector_return_decomposition(state)

        render :inline => "<%= image_tag '#{results[:file_names][0]}' %><br/><%= image_tag '#{results[:file_names][1]}' %>"
      }
    end
  end

  def render_style_return_decomposition
    respond_to do |wants|
      wants.js {

        holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
        tickers = holdings.map { |e| e[0] }
        shares = holdings.map { |e| e[1] }
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => shares})
          
        offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
        sliced_state = state.slice(offset) # ~5 years

        results = style_return_decomposition(sliced_state)
          
        render :inline => "<%= image_tag '#{results[:file_name]} %>"
      }
    end
  end

  def render_rate_return_sensitivity
    respond_to do |wants|
      wants.js {

        holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
        tickers = holdings.map { |e| e[0] }
        shares = holdings.map { |e| e[1] }
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => shares})
          
        offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
        sliced_state = state.slice(offset) # ~5 years

        results = rate_return_sensitivity(sliced_state)

        render :inline => "<%= image_tag '#{results[:file_name]}' %>"
      }
    end
  end

  def render_asset_return_decomposition
    respond_to do |wants|
      wants.js {

        holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
        tickers = holdings.map { |e| e[0] }
        shares = holdings.map { |e| e[1] }
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => shares})
          
        offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
        sliced_state = state.slice(offset) # ~5 years

        results = asset_return_decomposition(sliced_state)
        render :inline => "<%= image_tag '#{results[:file_names][0]}' %><br/><%= image_tag '#{results[:file_names][1]}' %>"
      }
    end
  end

  def render_up_down_capture
    respond_to do |wants|
      wants.js {

        holdings = session[:portfolio].tickers.zip(session[:portfolio].shares).sort_by { |e| e[0] }
        tickers = holdings.map { |e| e[0] }
        shares = holdings.map { |e| e[1] }
        state = Portfolio::State.new({:tickers => tickers,
            :number_of_shares => shares})
          
        offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
        sliced_state = state.slice(offset) # ~5 years

        results = up_down_capture(sliced_state)
          
        render :inline => "<%= image_tag '#{results[:file_name]}' %>"
      }
    end
  end

  def render_dimensionality_analysis
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

          results = dimensionality_analysis(portfolio_state)
           
          results[:num_unique_clusters].times { |i|
            inline_renderable += "<b>Cluster #{i+1}</b>: "
            inline_renderable += results[:identified_clusters].select { |k,v| v == i }.join(" ")
            inline_renderable += "<br/>"
          }
          inline_renderable += "<br/>"
 
          render :inline => inline_renderable
        end
      }
    end
  end

  ####################### ####################### #######################
  ####################### ####################### #######################
  ####################### ####################### #######################
  ####################### ####################### #######################
  private

  def correlation_analysis(state)
    correlation_matrix = state.sample_correlation_matrix

    # ipc = sum(i) sum(j) x(i)x(j)p(i,j) i != j
    ipc = state.weights * correlation_matrix * state.weights.col
    # now we have to subtract the correlation of 1 (diagonals)
    # subtract the sum of the weights squared
    ipc = ipc - state.weights * state.weights.col

    color_coded_correlation = {}

    correlation_matrix.to_a.each_with_index { |row, i|
      color_coded_correlation[state.tickers[i]] = {}
      row.each_with_index { |e,j|
        clamped = (e * 100).to_i / 100.0
        color = hsv_to_rgb_string(0, clamped.abs**2, 1.0)
        color_coded_correlation[state.tickers[i]][state.tickers[j]] = { :correlation => e, :color => color }
      }
    }

    ipc_pct = (1.0 - ipc)/2.0
    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@a,000000,1,#{ipc_pct}:.5,7,0
      ")

    file_name = "portfolio/heat_chart.png"
    File.open("public/images/#{file_name}", "w") { |f|
      f << image
    }

    return {
      :color_coded_correlation => color_coded_correlation,
      :ipc => ipc_pct,
      :file_name => file_name
    }
  end

  def volatility_analysis(state)
    window_size = 250
    sampling_period = 20
    tickers = state.tickers

    marginal_contributions = Portfolio::Risk.marginal_contribution_to_volatility(state.to_log_returns,
      state.log_returns, window_size, sampling_period)

    contributions = Portfolio::Risk.contributions_to_volatility(state, state.log_returns,
      window_size, sampling_period, marginal_contributions)

    sa = GoogleChart::StackedArea.new
    sa.title = "Annual Contribution to Volatility (measured monthly)"
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

    file_name = "portfolio/percent_contribution"
    sa.write_to("public/images/#{file_name}")

    expected_volatility = sliced_state.expected_volatility


    ncol = marginal_contributions.size2
    current_marginal_contributions = marginal_contributions.column(ncol-1).to_a
    marginal_contributions = {}
    tickers.size.times { |i|
      marginal_contributions[tickers[i]] = current_marginal_contributions[i]*1000
    }

    return {
      :expected_volatility => expected_volatility,
      :file_name => "#{file_name}.png",
      :marginal_contributions => marginal_contributions
    }
  end

  def expected_return_monte_carlo(state)

    mc_series = state.return_monte_carlo

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

    file_name = "portfolio/return_monte_carlo"
    #FIX: This seems like a rather ugly way to do this
    lc.write_to("public/images/#{file_name}", {:chdlp => 'b'})

    return { :file_name => "#{file_name}.png" }
  end

  def income_monte_carlo(state)
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
    file_name = "portfolio/income_monte_carlo"
    lc.write_to("public/images/#{file_name}", {:chdlp => 'b'})

    return {:file_name => "#{file_name}.png" }
  end

  def sector_allocation_analysis(state)
    tickers = state.tickers
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

    file_name = "portfolio/sector_allocation"
    pc.write_to("public/images/#{file_name}", {:chdlp => 'b'})

    return { :file_name => "#{file_name}.png" }
  end


  def risk_decomposition_analysis(state)
    composite_risk = Portfolio::Risk::ValueAtRisk.composite_risk(state, 250)

    portfolio_var = composite_risk[:portfolio_var]
    portfolio_cvar = composite_risk[:portfolio_cvar]
    individual_vars = composite_risk[:individual_vars]
    individual_cvars = composite_risk[:individual_cvars]
    marginal_vars = composite_risk[:marginal_vars]
    component_vars = composite_risk[:component_vars]

    risks = {}

    tickers.each_with_index { |ticker, i|
      risks[ticker] ||= {}
      risks[ticker][:individual_var] = individual_vars[i]
      risks[ticker][:individual_cvar] = individual_cvars[i]
      risks[ticker][:component_var] = component_vars[i]
      risks[ticker][:proportion_var] = component_vars[i] / portfolio_var
      risks[ticker][:marginal_var] = marginal_vars[i]
    }

    return {
      :portfolio_var => portfolio_var,
      :portfolio_cvar => portfolio_cvar,
      :holding_vars => risks
    }
  end

  def sector_return_decomposition(state)
    window_size = 125
    sampling_period = 10

    factors = Portfolio::Composition::ReturnAnalysis::SECTOR_PROXIES
    return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(state, factors, window_size, sampling_period)
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
    image_file_name = "portfolio/sector_return_decomposition"
    sa.write_to("public/images/#{image_file_name}", {:chdlp => 'b'})

    r2_file_name = "portfolio/sector_r-squared"
    lc.write_to("public/images/#{r2_file_name}", {:chdlp => 'b'})

    return { :file_names => ["#{image_file_name}.png", "#{r2_file_name}.png"] }
  end

  def style_return_decomposition(state)
    window_size = 120
    sampling_period = 10

    factors = Portfolio::Composition::ReturnAnalysis::STYLE_PROXIES
    return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(state, factors, window_size, sampling_period)
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

    file_name = "portfolio/style_return_decomposition"
    sc.write_to("public/images/#{file_name}", extras)

    return { :file_name => "#{file_name}.png" }
  end

  def rate_return_sensitivity(state)
    factors = Portfolio::Composition::ReturnAnalysis::RATE_PROXIES
    return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(state, factors, window_size, sampling_period)
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
    file_name = "portfolio/rate_and_credit_return_decomposition"
    sc.write_to("public/images/#{file_name}", extras)

    return { :file_name => "#{file_name}.png" }
  end

  def asset_return_decomposition(state)
    window_size = 125
    sampling_period = 10

    factors = Portfolio::Composition::ReturnAnalysis::ASSET_PROXIES
    return_values = Portfolio::Composition::ReturnAnalysis::composition_by_factors(state, factors, window_size, sampling_period)
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
    image_file_name = "portfolio/asset_return_decomposition"
    sa.write_to("public/images/#{image_file_name}", {:chdlp => 'b'})
    r2_file_name = "portfolio/asset_r-squared"
    lc.write_to("public/images/#{r2_file_name}", {:chdlp => 'b'})

    return { :file_names => ["#{image_file_name}.png", "#{r2_file_name}.png"] }
  end


  def up_down_capture(state)
    points = Portfolio::Risk::upside_downside_capture(state,
      {:tickers => ["IWM"], :number_of_shares => [1]}, 250, 5) << [1.0, 1.0]

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
    sc.title = "Annual Up / Down Capture Analysis|against Russell 2000 (measured weekly)"
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

    file_name = "portfolio/up_down_capture"
    sc.write_to("public/images/#{file_name}", extras)

    return { :file_name => "#{file_name}.png" }
  end

  def dimensionality_analysis(state)
    tickers = state.tickers
    eigen_values, percent_variance, eigen_vectors =
      Portfolio::Composition::ReturnAnalysis::pca(state)

    #identify which dimension to associate a holding with
    identified_dimension = Array.new(tickers.size)
    sqrt_variance = percent_variance.map { |e| Math.sqrt(e) }
    tickers.size.times { |i|
      # take the eigen_vector matrix
      # and for each column in our correlation matrix,
      # solve for our betas.  find the max beta, and use that as
      # our identified dimension
      c, cov, chisq, status = GSL::MultiFit::linear(eigen_vectors.transpose, state.sample_correlation_matrix.column(i))
      identified_dimension[i] = (c * sqrt_variance).map {|e| e.abs }.sort_index[-1]
    }

    unique_dimensions = identified_dimension.uniq.sort

    clusters = Cluster.hierarchical(state.sample_correlation_matrix, unique_dimensions.size)
    identified_clusters = {}
    clusters.map { |e| e.each { |i| identified_clusters[tickers[i]] = i }}

    return { :identified_clusters => identified_clusters,
      :num_unique_clusters => unique_dimensions.size }
  end
=begin
  def optimize
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
  end
=end

end