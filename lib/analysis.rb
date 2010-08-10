module Analysis
  include Colors

  private
  def correlation_analysis(state)
    correlation_matrix = state.sample_correlation_matrix

    # ipc = sum(i) sum(j) x(i)x(j)p(i,j)
    #theoretically, (state.weights.col * state.weights).to_v.sum should equal 1
    #but why risk numerical innacuracy?
    ipc = (state.weights * correlation_matrix * state.weights.col) / (state.weights.col * state.weights).to_v.sum
    # now we have to subtract the correlation of 1 (diagonals)
    # subtract the sum of the weights squared

    color_coded_correlation = {}

    correlation_matrix.to_a.each_with_index { |row, i|
      color_coded_correlation[state.tickers[i]] = {}
      row.each_with_index { |e,j|
        clamped = (e * 100).to_i / 100.0
        color = hsv_to_rgb_string(0, clamped.abs**2, 1.0)
        color_coded_correlation[state.tickers[i]][state.tickers[j]] = { :correlation => e, :color => color }
      }
    }

    draw_down_correlation_matrix = state.compute_draw_down_correlation

    dd_color_coded_correlation = {}

    draw_down_correlation_matrix.to_a.each_with_index { |row, i|
      dd_color_coded_correlation[state.tickers[i]] = {}
      row.each_with_index { |e,j|
        clamped = (e * 100).to_i / 100.0
        color = hsv_to_rgb_string(0, clamped.abs**2, 1.0)
        dd_color_coded_correlation[state.tickers[i]][state.tickers[j]] = { :correlation => e, :color => color }
      }
    }

    dd_ipc = (state.weights * draw_down_correlation_matrix * state.weights.col) / (state.weights.col * state.weights).to_v.sum
    dd_ipc_pct = (1.0 - dd_ipc) / 2.0

    ipc_pct = (1.0 - ipc)/2.0
    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(ipc_pct*10000).to_i / 100.0},000000,1,#{ipc_pct}:.5,16,0
      ")

    file_name = "portfolio/correlation_heat_chart.png"
    File.open("public/images/#{file_name}", "w") { |f|
      f << image
    }

    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(dd_ipc_pct*10000).to_i / 100.0},000000,1,#{dd_ipc_pct}:.5,16,0
      ")

    dd_file_name = "portfolio/dd_correlation_heat_chart.png"
    File.open("public/images/#{dd_file_name}", "w") { |f|
      f << image
    }

    marginal_change = {}
    state.tickers.each_with_index { |ticker,i|
      t_correlation_matrix = correlation_matrix.clone.to_a
      t_correlation_matrix.delete_at(i) #delete the ith row
      t_correlation_matrix.each { |a| a.delete_at(i) } #delete the ith column too

      t_correlation_matrix = GSL::Matrix[*t_correlation_matrix]

      weights = state.weights.clone
      weights.delete_at(i)
      weights = weights / weights.abs.sum #recompute weights

      #theoretically, (state.weights.col * state.weights).to_v.sum should equal 1
      #but why risk numerical innacuracy?
      indiv_ipc = (weights * t_correlation_matrix * weights.col) / (state.weights.col * state.weights).to_v.sum
      indiv_ipc = (1.0 - indiv_ipc) / 2.0

      t_dd_correlation_matrix = draw_down_correlation_matrix.clone.to_a
      t_dd_correlation_matrix.delete_at(i) #delete the ith row
      t_dd_correlation_matrix.each { |a| a.delete_at(i) } #delete the ith column too

      t_dd_correlation_matrix = GSL::Matrix[*t_dd_correlation_matrix]

      dd_indiv_ipc = (weights * t_dd_correlation_matrix * weights.col) / (state.weights.col * state.weights).to_v.sum
      dd_indiv_ipc = (1.0 - dd_indiv_ipc) / 2.0

      marginal_change[ticker] = {:ipc => (ipc_pct - indiv_ipc) / state.weights[i],
        :dd_ipc => (dd_ipc_pct - dd_indiv_ipc) / state.weights[i] }
    }

    return {
      :color_coded_correlation => color_coded_correlation,
      :score => ipc_pct,
      :file_name => file_name,

      :dd_color_coded_correlation => dd_color_coded_correlation,
      :dd_score => dd_ipc_pct,
      :dd_file_name => dd_file_name,
      :marginal_change => marginal_change
    }
  end

  def volatility_analysis(state)
    window_size = 125
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

    expected_volatility = state.expected_volatility

    ncol = marginal_contributions.size2
    current_marginal_contributions = marginal_contributions.column(ncol-1).to_a
    marginal_contributions = {}
    tickers.size.times { |i|
      marginal_contributions[tickers[i]] = current_marginal_contributions[i]*1000
    }

    columns = contributions.size2
    current_contributions = contributions.column(columns-2)
    total_current_contribution = current_contributions.abs.sum
    contributions = {}
    tickers.size.times { |i|
      contributions[tickers[i]] = current_contributions[i].abs / total_current_contribution
    }

    return {
      :expected_volatility => expected_volatility,
      :file_name => "#{file_name}.png",
      :marginal_contributions => marginal_contributions,
      :contributions => contributions
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
    #we would do income_stream[-1] here, but then we have the potential to
    #be between quarters, where everything hasn't been payed out yet...
    initial_income = state.to_income_stream[-2]

    x_data = [1,2,3,4]

    means = (mc_series[:means]).to_a
    #means.unshift(initial_income)

    one_std_above = (mc_series[:means] +
        mc_series[:upside_standard_deviations]).to_a
    #one_std_above.unshift(initial_income)

    two_std_above = (mc_series[:means] +
        2.0 * mc_series[:upside_standard_deviations]).to_a
    #two_std_above.unshift(initial_income)

    one_std_below = (mc_series[:means] -
        mc_series[:downside_standard_deviations]).to_a
    #one_std_below.unshift(initial_income)

    two_std_below = (mc_series[:means] -
        2.0 * mc_series[:downside_standard_deviations]).to_a
    #two_std_below.unshift(initial_income)

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

    tickers.each { |ticker|
      company = Company.new({:ticker => ticker.downcase})

      if available_sectors.include?(company.sector)
        sector_hash[company.sector] += 1
      else
        sector_hash['Other'] += 1
      end
    }

    colors = random_colors(sector_hash.size)

    i = 0
    pc = GoogleChart::PieChart.new
    sector_hash.keys.sort.each { |k|
      clamped = ((sector_hash[k] / tickers.size.to_f) * 10000).to_i / 100.0
      #Rails.logger.info(sector_hash[k])
      pc.data "#{k} (#{sector_hash[k].to_i} at #{clamped}%)", sector_hash[k], colors[i]
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

    cc = 0.0
    state.tickers.each_with_index { |ticker, i|
      risks[ticker] ||= {}
      risks[ticker][:individual_var] = individual_vars[i]
      risks[ticker][:individual_cvar] = individual_cvars[i]
      risks[ticker][:component_var] = component_vars[i]
      risks[ticker][:proportion_var] = component_vars[i] / portfolio_var

      cc = cc + risks[ticker][:proportion_var] ** 2
      risks[ticker][:marginal_var] = marginal_vars[i]
    }

    cc = 1.0 / cc
    cc = cc / state.tickers.size

    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(cc*10000).to_i / 100.0},000000,2,#{cc}:.5,16,2
      ")

    file_name = "portfolio/risk_heat_chart.png"
    File.open("public/images/#{file_name}", "w") { |f|
      f << image
    }

    return {
      :file_name => file_name,
      :portfolio_var => portfolio_var,
      :portfolio_cvar => portfolio_cvar,
      :holding_vars => risks,
      :score => cc
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
    window_size = 125
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
    window_size = 125
    sampling_period = 10
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
      {:tickers => ["IWV"], :number_of_shares => [1]}, 250, 5) << [1.0, 1.0]

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

    up_down_file_name = "portfolio/up_down_capture"
    sc.write_to("public/images/#{up_down_file_name}", extras)


    #given left, right, top, bottom, we can find intersection point and area
    #of 1:1 line
    rect_size = (right - left) * (top - bottom)

    area_above = nil
    if bottom > right
      area_above = 1.0
    elsif top < left
      area_above = 0.0
    elsif top < right
      if left > bottom # intersection on the left side
        Rails.logger.info("Intersected top and left")
        triangle_size = ((top - left)**2) / 2.0
        area_above = triangle_size / rect_size
      else
        Rails.logger.info("Intersected top and bottom")
        # find the left rectangle size
        lrect = (top - bottom) * (bottom - left)
        # find the rest of the triangle
        tri = ((top - bottom) ** 2) / 2

        area_above = (lrect + tri) / rect_size
      end
    elsif right < top # intersection on the right side
      if right > bottom
        Rails.logger.info("Intersected right and bottom")
        triangle_size = ((right - bottom)**2) / 2.0
        area_above = 1.0 - triangle_size / rect_size
      else
        Rails.logger.info("Intersected right and left")
        lrect = (top - right) * (right - left)
        tri = ((right - left) ** 2) / 2

        area_above = (lrect + tri) / rect_size
      end
    else #corner case -- exact corner intersection
      area_above = 0.5
    end

    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(area_above*10000).to_i / 100.0},000000,2,#{area_above}:.5,16,2
      ")

    spectrum_file_name = "portfolio/up_down_heat_chart.png"
    File.open("public/images/#{spectrum_file_name}", "w") { |f|
      f << image
    }

    return { :file_names => ["#{up_down_file_name}.png", spectrum_file_name] ,
      :score => area_above }
  end

  def dimensionality_analysis(state)
    tickers = state.tickers
    shares = state.number_of_shares
    dates = state.dates
    time_series = state.time_series

    eigen_values, percent_variance, eigen_vectors =
      Portfolio::Composition::ReturnAnalysis::pca(state)

=begin
    w, h = state.sample_correlation_matrix.nmf(25)
    Rails.logger.info(w)
    Rails.logger.info(h)
    Rails.logger.info(w*h)

    Rails.logger.info(GSL::Matrix::NMF.difcost(state.sample_correlation_matrix, w*h))
=end
    
    #should we be sqrting the eigen-values here?
    m = eigen_vectors * GSL::Matrix.diagonal(eigen_values.map { |e| Math.sqrt(e) })
    #identify which dimension to associate a holding with
    positions = GSL::Matrix.alloc(tickers.size, m.size2)
    tickers.size.times { |i|
      # take the eigen_vector matrix
      # and for each column in our correlation matrix,
      # solve for our betas.  find the max beta, and use that as
      # our identified dimension
      c, cov, chisq, status = GSL::MultiFit::linear(m, state.sample_correlation_matrix.column(i))
      positions.set_row(i, c)
    }

    n_holdings = tickers.size
    n_dimensions = 2

    number_of_dimensions = n_holdings * n_dimensions

    # preallocate -- which means we can't go multithreaded here...
    cosine_matrix = GSL::Matrix.calloc(n_holdings, n_holdings)
    positions = GSL::Matrix.calloc(n_holdings, n_dimensions)

    #######################

    my_f = Proc.new { |fly_position|
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

      state.weights * (state.sample_correlation_matrix - cosine_matrix).map{|e| e**2} * state.weights.col
    }

    my_func = GSL::MultiMin::Function.alloc(my_f, number_of_dimensions)

    x = GSL::Vector.alloc(Array.new(number_of_dimensions).map! {rand})
    ss = GSL::Vector.alloc(number_of_dimensions)
    ss.set_all(1.0)

    minimizer = GSL::MultiMin::FMinimizer.alloc("nmsimplex", number_of_dimensions)
    minimizer.set(my_func, x, ss)

    Status.info("Minimizing projected distance to correlation matrix in #{n_dimensions} dimensions")
    begin
      status = minimizer.iterate()
      status = minimizer.test_size(1e-2)
    end while status == GSL::CONTINUE
    Status.info("FVal: #{minimizer.fval}")
    features = minimizer.x

    positions = GSL::Matrix.alloc(n_holdings, n_dimensions)
    tickers.size.times { |i|
      v = features.get(i*n_dimensions, n_dimensions).normalize
      positions.set_row(i, v)
    }

    colors = random_colors(tickers.size)
    img = Magick::Image.new(501,501)
    Magick::Draw.new.fill('#000000').circle(501/2,501/2,0,501/2).draw(img)
    positions.size1.times { |i|
      position = positions.row(i)
      Magick::Draw.new.stroke("##{colors[i]}").stroke_width((Math.sqrt(50*state.weights[i])).ceil).line(501/2,501/2,501/2*(1 + position[0]), 501/2*(1 + position[1])).draw(img)
    }
    img.write('public/images/portfolio/correlation_circle.png')

    #######################

    dd_correlation_matrix = state.compute_draw_down_correlation

    my_f = Proc.new { |fly_position|
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
      state.weights * (dd_correlation_matrix - cosine_matrix).map{|e| e**2} * state.weights.col
    }

    my_func = GSL::MultiMin::Function.alloc(my_f, number_of_dimensions)

    x = GSL::Vector.alloc(Array.new(number_of_dimensions).map! {rand})
    ss = GSL::Vector.alloc(number_of_dimensions)
    ss.set_all(1.0)

    minimizer = GSL::MultiMin::FMinimizer.alloc("nmsimplex", number_of_dimensions)
    minimizer.set(my_func, x, ss)

    Status.info("Minimizing projected distance to dd-correlation matrix in #{n_dimensions} dimensions")
    begin
      status = minimizer.iterate()
      status = minimizer.test_size(1e-2)
    end while status == GSL::CONTINUE
    Status.info("FVal: #{minimizer.fval}")

    features = minimizer.x

    positions = GSL::Matrix.alloc(n_holdings, n_dimensions)
    tickers.size.times { |i|
      v = features.get(i*n_dimensions, n_dimensions).normalize
      positions.set_row(i, v)
    }

    img = Magick::Image.new(501,501)
    Magick::Draw.new.fill('#000000').circle(501/2,501/2,0,501/2).draw(img)
    positions.size1.times { |i|
      position = positions.row(i)
      Magick::Draw.new.stroke("##{colors[i]}").stroke_width((Math.sqrt(50*state.weights[i])).ceil).line(501/2,501/2,501/2*(1 + position[0]), 501/2*(1 + position[1])).draw(img)
    }
    img.write('public/images/portfolio/dd_correlation_circle.png')

    #######################

    clusters = Cluster.hierarchical(positions, Math.sqrt(tickers.size))
    identified_clusters = {}
    clusters.each_with_index { |e,i|
      e.each { |j|
        identified_clusters[tickers[j]] = i
      }
    }
    Rails.logger.info(clusters)

    cluster_values = Hash.new(0.0)
    total_value = 0.0
    tickers.each_with_index { |ticker, i|
      cluster_values[identified_clusters[ticker]] += shares[i] * time_series[ticker][dates[-1]]
      total_value += shares[i] * time_series[ticker][dates[-1]]
    }
    cluster_weights = Hash[*(cluster_values.map { |k,v| [k, v/total_value]}.flatten)]

    cc = 1.0 / cluster_weights.inject(0.0) { |s,p| s + p[1]**2 }
    score = [cc / [Math.sqrt(tickers.size), 3.0].max, 1.0].min

    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(score*10000).to_i / 100.0},000000,1,#{score}:.5,16,0
      ")

    file_name = "portfolio/dimensionality_heat_chart.png"
    File.open("public/images/#{file_name}", "w") { |f|
      f << image
    }

    # ideal number of clusters is?  Math.sqrt(ticker.size)
    # and ideally, the amount of wealth in each cluster would be equal
    return { :identified_clusters => identified_clusters,
      :num_unique_clusters => clusters.size,
      :file_name => file_name,
      :score => score,
      :correlation_circles => ['portfolio/correlation_circle.png',
        'portfolio/dd_correlation_circle.png']
    }
  end
end
