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
      session[:portfolio].tickers.map! { |t| t.upcase }
      redirect_to :action => :analyze
    end
  end

  def render_report
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

      # color_coded_correlation, file_name, score
      cor_results = correlation_analysis(state)

      # expected_volatility, file_name, marginal_contributions
      v_results = volatility_analysis(state)

      # portfolio_var, portfolio_cvar
      # holding_vars
      #     individual_var
      #     individual_cvar
      #     component_var
      #     proportion_var
      #     marginal_var
      # file_name
      # score
      rd_results = risk_decomposition_analysis(state)

      sa_analysis = true
      begin
        # file_names
        sa_results = sector_allocation_analysis(state)
      rescue
        sector_analysis = false
      end

      rmc_analysis = true
      begin
        # file_name
        rmc_results = expected_return_monte_carlo(state)
      rescue
        rmc_analysis = false
      end

      imc_analysis = true
      begin
        # file_name
        imc_results = income_monte_carlo(state)
      rescue
        imc_analysis = false
      end

      sec_analysis = true
      begin
        # file_names
        sec_results = sector_return_decomposition(state)
      rescue
        sec_analysis = false
      end
          
      # file_names
      ar_analysis = true
      begin
        ar_results = asset_return_decomposition(state)
      rescue
        ar_analysis = false
      end

      rs_analysis = true
      begin
        # file_name
        rs_results = rate_return_sensitivity(state)
      rescue
        rs_analysis = false
      end

      sr_analysis = true
      begin
        # file_name
        sr_results = style_return_decomposition(state)
      rescue
        sr_analysis = false
      end

      ud_results = up_down_capture(state)

      # identified_clusters, num_unique_clusters, file_name, score
      dim_results = dimensionality_analysis(state)

      cluster_colors = random_colors(dim_results[:num_unique_clusters])

      pdf_handle = "public/report.pdf"
      Prawn::Document.generate(pdf_handle,
        :page_layout => :landscape,
        :info => {
          :Title => "Portfolio Analysis",
          :Author => "Newfound Research, LLC",
          :Subject => "Portfolio Decomposition",
          :Creator => "Newfound Research, LLC",
          :CreationDate => Time.now
        } ) do

        font 'Helvetica'
        self.font_size = 8
        repeat :all do
          draw_text "Copyright Newfound Research, LLC", :at => bounds.top_left
        end

        
        self.font_size = 32
        move_down 175
        text "Newfound Portfolio Diagnotistics", :align => :center

        self.font_size = 8
        move_down 200
        font 'Helvetica', :style => :bold
        text "Limitation of Liability"
        font 'Helvetica'
        text "This data is not intended to provide any investment or related advice, and is not intended to serve as an offer to sell any security or any other investment product or service."

        font 'Helvetica', :style => :bold
        text "\nInformation Provided \"As Is\""
        font 'Helvetica'
        text "Information is provided AS IS without any express or implied warranty of any kind."
        
        font 'Helvetica', :style => :bold
        text "\nNo Investment Advice or Offer"
        font 'Helvetica'
        text "None of Newfound Research, its directors, officers, employees, agents or affiliates shall be responsible for any claims, losses, liability, costs or other damages, including but not limited to trading losses or lost profits (whether direct, indirect, consequential, incidental or special), that result from the use of this information, or a disruption in such use, even if Newfound Research has been notified of the possibility of such claims, losses, costs or other damages. Some states and other jurisdictions may prohibit certain limitations of liability, so this may not apply to you."

        ####### PORTFOLIO INFORMATION

        start_new_page
        self.font_size = 32
        move_down 175
        text "Analysis of Portfolio", :align => :center

        start_new_page
        move_down 10
        self.font_size = 16
        text "Portfolio Statistics", :align => :center
        move_down 10
        self.font_size = 12
        text "Annual Expected Portfolio Variance: #{(v_results[:expected_volatility]*10000).to_i/100.0}%"
        text "Annual Portfolio Value-at-Risk: #{(rd_results[:portfolio_var]*10000).to_i/100.0}%"
        text "Annual Portfolio Conditional Value-at-Risk: #{(rd_results[:portfolio_cvar]*10000).to_i/100.0}%"

        move_down 20
        self.font_size = 13
        text "Diversification Score", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{cor_results[:file_name]}"
        image img_handle, :position => :center

        move_down 20
        self.font_size = 13
        text "Risk Concentration Score", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{rd_results[:file_name]}"
        image img_handle, :position => :center

        move_down 20
        self.font_size = 13
        text "Dimensionality Score", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{dim_results[:file_name]}"
        image img_handle, :position => :center

        move_down 20
        self.font_size = 13
        text "Market Capture Score", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{ud_results[:file_names][1]}"
        image img_handle, :position => :center

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 100
          #text "Sector Allocation", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{sa_results[:file_name]}"
          image img_handle, :position => :center
        end if sa_analysis

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 100
          text "Daily Projection of Portfolio Value", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{rmc_results[:file_name]}"
          image img_handle, :position => :center

          self.font_size = 12
          move_down 20
          text "Portfolio Value projection is performed using a Monte-Carlo simulation.  " +
            "To perform this simulation, a block-bootstrapping method is utilized, " +
            "where historic log-returns over a 5-year period are sampled in two-week " +
            "periods and other 'possible' returns are constructed.  This methodology is " +
            "utilized because it is able to capture the correlation structure of the underlying " +
            "holdings, as well as autocorrelation, without making any assumptions about the " +
            "underlying distribution."
        end if rmc_analysis

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 50
          text "Quarterly Projection of Portfolio Income", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{imc_results[:file_name]}"
          image img_handle, :position => :center

          self.font_size = 12
          move_down 20
          text "Income projection is performed utilizing a similar Monte-Carlo simulation " +
            "as portfolio value projection, but utilizes dividend growth history.  This " +
            "projection works best for holdings with stable dividend histories."
        end if imc_analysis

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 50
          text "Sector Contribution Analysis", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{sec_results[:file_names][0]}"
          image img_handle, :position => :center, :fit => [500, 400]
          img_handle = "#{RAILS_ROOT}/public/images/#{sec_results[:file_names][1]}"
          image img_handle, :position => :center, :fit => [500, 200]

          self.font_size = 12
          move_down 20
          text "This graph provides insight as to how returns may have been replicated " +
            "or attributed to a portfolio of sector proxy holdings.  While companies are " +
            "classified into a single sector, their corporate performance is " +
            "impacted by the economy as a whole.  Analyzing return attribution to sectors " +
            "can allow you to identify exposures to sectors that may not have been obvious " +
            "at first glance."
        end if sec_analysis

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 50
          text "Asset Contribution Analysis", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{ar_results[:file_names][0]}"
          image img_handle, :position => :center, :fit => [500, 400]
          img_handle = "#{RAILS_ROOT}/public/images/#{ar_results[:file_names][1]}"
          image img_handle, :position => :center, :fit => [500, 200]

          self.font_size = 12
          move_down 20
          text "Much like sector return attribution, asset return attribution gives insight " +
            "into the corporate exposure to macro-economic asset classes of holdings in the " +
            "portfolio."
        end if ar_analysis


        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 50
          text "Style Drift Analysis", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{sr_results[:file_name]}"
          image img_handle, :position => :center
        end if sr_analysis

        begin
          start_new_page
          move_down 10
          self.font_size = 16
          move_down 50
          text "Credit & Term Sensitivity Analysis", :align => :center
          img_handle = "#{RAILS_ROOT}/public/images/#{rs_results[:file_name]}"
          image img_handle, :position => :center
        end if rs_analysis

        start_new_page
        move_down 10
        self.font_size = 16
        move_down 50
        text "Up / Down Capture Analysis", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{ud_results[:file_names][0]}"
        image img_handle, :position => :center, :fit => [350, 350]

        self.font_size = 12
        move_down 5
        text "Typical Up / Down capture analysis determines, compared to a benchmark, " +
          "how much of the upside return a portfolio captured versus how much of the " +
          "downside it incurred.  We feel that this does not truly identify the risk-aversion " +
          "investors display, so we utilize a method where down-side capture is measured as " +
          "the percent return required for the portfolio to return to parity versus the percent " +
          "return required for the benchmark to return to parity.  A negative up-side capture " +
          "indicates that the portfolio loses value when the benchmark goes up, and a negative " +
          "down-side capture indicates that the portfolio gains value when the benchmark loses it."
        
        start_new_page
        move_down 10
        self.font_size = 16
        text "Correlation Analysis"
        move_down 10

        corr_font_size = [[(200.0 / tickers.size).to_i, 6].max, 16].min
        self.font_size = corr_font_size
        # generate our rows
        rows = []
        rows << [""] + tickers
        tickers.each { |t1|
          row = []
          row << t1
          tickers.each { |t2|
            row << (((cor_results[:color_coded_correlation][t1][t2][:correlation] * 100).to_i)/100.0).to_s
          }
          rows << row
        }

        table(rows,
          :cell_style => { :padding => 1 },
          :header => true,
          :width => bounds.width) do
          cells.borders = []
          # Use the row() and style() methods to select and style a row.

          row(0).style(:style => :bold, :background_color => 'cccccc')
          column(0).style(:style => :bold, :background_color => 'cccccc')
          row(0).column(0).style(:background_color => 'ffffff')

          tickers.each_with_index { |t1,i|
            tickers.each_with_index { |t2,j|
              row(i+1).column(j+1).style(:background_color => cor_results[:color_coded_correlation][t1][t2][:color])
            }
          }

          columns(1..tickers.size).style(:align => :center)

        end

        ####### HOLDING INFORMATION

        start_new_page
        self.font_size = 7
        headers = ["Name", "Ticker", "Sector", "Shares", "Value ($)", "Weight (%)",
          "Contr. to Portfolio\n Volatility (%)",
          "Marginal\nVolatility (bp)", "VaR (%)", "CVaR (%)",
          "Marginal VaR (bp)", "Risk Allocation",
          "Contribution to\nDiversification (%)",
          "Marginal Diversification"]

        rows = []
        cluster_stats = {}
 
        tickers.each_with_index { |ticker, i|
          cluster = dim_results[:identified_clusters][ticker]
          cluster_stats[cluster] ||= Hash.new(0.0)
          
          #FIX: This should be refactored into the correlation matrix section...
          correlation_matrix = state.sample_correlation_matrix.clone.to_a
          correlation_matrix.delete_at(i) #delete the ith row
          correlation_matrix.each { |a| a.delete_at(i) } #delete the ith column too
          
          correlation_matrix = GSL::Matrix[*correlation_matrix]

          weights = state.weights.clone
          weights.delete_at(i)
          weights = weights / weights.abs.sum #recompute weights

          #theoretically, (state.weights.col * state.weights).to_v.sum should equal 1
          #but why risk numerical innacuracy?
          indiv_ipc = (weights * correlation_matrix * weights.col) / (state.weights.col * state.weights).to_v.sum
          indiv_ipc = (1.0 - indiv_ipc) / 2.0

          #Rails.logger.info(cor_results[:score] - indiv_ipc)
          
          String.send(:include, StringExtensions)

          value = (shares[i] * state.time_series[ticker][state.dates[-1]])
          weight = (state.weights[i]*10000).to_i / 100.0
          vol_contribution = ((v_results[:contributions][ticker] * 10000).to_i)/ 100.0
          risk_contribution = (rd_results[:holding_vars][ticker][:proportion_var] * 10000).to_i / 100.0
          diversification_contribution = ((((cor_results[:score] - indiv_ipc) / cor_results[:score])*10000).to_i / 100.0)

          rows << [state.companies[ticker].name.three_dot_chop(20),
            ticker,
            state.companies[ticker].sector,
            shares[i].to_s,
            "#{value.to_s}",
            "#{weight.to_s}",
            "#{vol_contribution.to_s}",
            "#{(((v_results[:marginal_contributions][ticker] * 100).to_i)/100.0).to_s}",
            "#{((rd_results[:holding_vars][ticker][:individual_var] * 10000).to_i / 100.0).tso_s}",
            "#{((rd_results[:holding_vars][ticker][:individual_cvar] * 10000).to_i / 100.0).to_s}",
            "#{((rd_results[:holding_vars][ticker][:marginal_var] * 10000).to_i / 100.0).to_s}",
            "#{risk_contribution.to_s}",
            "#{diversification_contribution.to_s}",
            "#{((((cor_results[:score] - indiv_ipc) / state.weights[i]) * 100).to_i / 100.0).to_s}"]

          cluster_stats[cluster][:total_value] += value
          cluster_stats[cluster][:total_weight] += weight
          cluster_stats[cluster][:total_volatility] += vol_contribution
          cluster_stats[cluster][:total_risk] += risk_contribution
          cluster_stats[cluster][:total_diversification] += diversification_contribution
          cluster_stats[cluster][:color] = cluster_colors[cluster] #overwrite color...
        }
        rows << Array.new(13, "")

        cluster_stats.each_with_index { |e,i|
          k, v = e
          rows << ["Cluster #{i+1}", "", "", "", v[:total_value].to_s,
            v[:total_weight].to_s, v[:total_volatility].to_s, "", "", "", "",
            v[:total_risk].to_s, v[:total_diversification].to_s, ""]
        }
        
        self.font_size = 32
        move_down 175
        text "Analysis of Holdings", :align => :center

        start_new_page

        self.font_size = 6
        move_down 10
        table([headers] + rows,
          :cell_style => { :padding => 3 },
          :header => true,
          :width => bounds.width) do
          cells.borders = []
          # Use the row() and style() methods to select and style a row.
          row(0).style(:style => :bold, :background_color => 'cccccc', :align => :center)
          tickers.each_with_index { |ticker,i|
            row(i+1).style(:background_color => cluster_colors[dim_results[:identified_clusters][ticker]])
          }

          cluster_stats.each_with_index { |e,i|
            k,v = e
            row(tickers.size+2+i).style(:background_color => v[:color])
          }


          columns(1...headers.size).style(:align => :center)
        end

        ######## DESCRIPTION OF METHODOLOGY & TERMS
        start_new_page
        move_down 20
        self.font_size = 32
        text "Process & Definitions"
        self.font_size = 12
        move_down 50
        text "Marginal Volatility is ..."
        text "Marginal Value-at-Risk is ..."

        self.font_size = 8
        number_pages "<page>", bounds.bottom_right #, :align => :right
      end

      render :inline => "<a href='/report.pdf'>Download</a>"
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
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t.gsub('-', '.').upcase}</b></font></td>"
          }
          inline_renderable += "<tr>"

          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # 5 years

          # color_coded_correlation, ipc, filename
          results = correlation_analysis(sliced_state)

          tickers.each { |t1|
            inline_renderable += "<tr>"
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t1.gsub('-', '.').upcase}</b></font></td>"
            tickers.each { |t2|
              color = results[:color_coded_correlation][t1][t2][:color]
              correlation = results[:color_coded_correlation][t1][t2][:correlation]
              clamped = (correlation * 100).to_i / 100.0
              inline_renderable += "<td bgcolor=\"#{color}\"><font size=\"#{font_size}\">#{clamped}</font></td>"
            }
            inline_renderable += "</tr>"
          }

          ipc_pct = results[:score]

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

          inline_renderable += "<h3>Marginal Contribution to Volatility</h3>"
          tickers.each_with_index { |ticker, i|
            inline_renderable += "<b>#{ticker}</b>: #{marginal_contributions[ticker]}<br/>"
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

          inline_renderable += "<br/><h3>Proportion of Portfolio VaR</h3><br/>"
          tickers.each { |ticker|
            inline_renderable += "<b>#{ticker}</b>: #{results[:holding_vars][ticker][:proportion_var]}<br/>"
          }

          inline_renderable += "<br/><%= image_tag '#{results[:file_name]}' %>"

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

        results = sector_return_decomposition(sliced_state)

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
          
        render :inline => "<%= image_tag '#{results[:file_name]}' %>"
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

        inline_renderable = "<%= image_tag '#{results[:file_names][0]}' %>"
        inline_renderable += "<br/>% Area Above: #{results[:score]}"
        inline_renderable += "<br/><%= image_tag '#{results[:file_names][1]}' %>"
          
        render :inline => inline_renderable
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

          #Rails.logger.info(results[:identified_clusters])
          results[:num_unique_clusters].times { |i|
            inline_renderable += "<b>Cluster #{i+1}</b>: "
            inline_renderable += results[:identified_clusters].select { |k,v| v == i }.map { |k,v| k }.join(" ")
            inline_renderable += "<br/>"
          }
          inline_renderable += "<br/><b>Wealth Distribution Across Clusters:"

          inline_renderable += "<br/><%= image_tag '#{results[:file_name]}' %>"
 
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

    ipc_pct = (1.0 - ipc)/2.0
    #weird fucking hack to get the http get to go through ... requires a newline?!
    image = Net::HTTP.get('http://chart.apis.google.com', "/chart?cht=lc&chs=400x75&chbh=14,0,0&chd=t:100|0,100&chco=00000000&chf=c,lg,0,00d10f,1,4ed000,0.8,c8d500,0.6,f07f00,0.30,d03000,0.10,ad0000,0&chxp=0,8,30,50,70,90|1,8,30,50,70,90&chm=@f#{(ipc_pct*10000).to_i / 100.0},000000,1,#{ipc_pct}:.5,16,0
      ")

    file_name = "portfolio/correlation_heat_chart.png"
    File.open("public/images/#{file_name}", "w") { |f|
      f << image
    }

    return {
      :color_coded_correlation => color_coded_correlation,
      :score => ipc_pct,
      :file_name => file_name
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

    #identify which dimension to associate a holding with
    identified_dimension = Array.new(tickers.size)
    tickers.size.times { |i|
      # take the eigen_vector matrix
      # and for each column in our correlation matrix,
      # solve for our betas.  find the max beta, and use that as
      # our identified dimension
      c, cov, chisq, status = GSL::MultiFit::linear(eigen_vectors.transpose, state.sample_correlation_matrix.column(i))
      identified_dimension[i] = (c * percent_variance.map { |e| Math.sqrt(e) }).map {|e| e.abs }.sort_index[-1]
    }

    unique_dimensions = identified_dimension.uniq.sort

    clusters = Cluster.hierarchical(state.sample_correlation_matrix, unique_dimensions.size)
    identified_clusters = {}
    clusters.each_with_index { |e,i|
      e.each { |j|
        identified_clusters[tickers[j]] = i
      }
    }

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
      :num_unique_clusters => unique_dimensions.size,
      :file_name => file_name,
      :score => score }
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

    ipc = weights * select_portfolio_state.sample_correlation_matrix * weights.col / (state.weights.col * state.weights).to_v.sum

    select_tickers.zip(weights.to_a) { |t,w|
      inline_renderable += "#{t}: #{w}<br/>"
    }
    inline_renderable += "<br/><b>IPC:</b> #{100*(1.0 - ipc)/2.0}%<br/>"
  end
=end

end