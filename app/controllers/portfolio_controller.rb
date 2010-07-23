class PortfolioController < ApplicationController
  include Analysis
  include Colors
  
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
        text "DD-Diversification Score", :align => :center
        img_handle = "#{RAILS_ROOT}/public/images/#{cor_results[:dd_file_name]}"
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

        start_new_page
        move_down 10
        self.font_size = 16
        text "Correlation Visualization"
        img_handle = "#{RAILS_ROOT}/public/images/#{dim_results[:correlation_circles][0]}"
        image img_handle, :position => :center, :fit => [500, 500]

        start_new_page
        move_down 10
        self.font_size = 16
        text "Draw-Down Correlation Analysis"
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
            row << (((cor_results[:dd_color_coded_correlation][t1][t2][:correlation] * 100).to_i)/100.0).to_s
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
              row(i+1).column(j+1).style(:background_color => cor_results[:dd_color_coded_correlation][t1][t2][:color])
            }
          }

          columns(1..tickers.size).style(:align => :center)

        end

        start_new_page
        move_down 10
        self.font_size = 16
        text "Draw-Down Correlation Visualization"
        img_handle = "#{RAILS_ROOT}/public/images/#{dim_results[:correlation_circles][1]}"
        image img_handle, :position => :center, :fit => [500, 500]

        ####### HOLDING INFORMATION

        start_new_page
        self.font_size = 7
        headers = ["Name", "Ticker", "Sector", "Shares", "Value ($)", "Weight (%)",
          "Contr. to Portfolio\n Volatility (%)",
          "Marginal\nVolatility (bp)", "VaR (%)", "CVaR (%)",
          "Marginal VaR (bp)", "Risk Allocation",
          "Marginal IPC", "Marginal DD-IPC"]

        rows = []
        cluster_stats = {}
 
        tickers.each_with_index { |ticker, i|
          cluster = dim_results[:identified_clusters][ticker]
          cluster_stats[cluster] ||= Hash.new(0.0)
          
          String.send(:include, StringExtensions)

          value = (shares[i] * state.time_series[ticker][state.dates[-1]])
          weight = (state.weights[i]*10000).to_i / 100.0
          vol_contribution = ((v_results[:contributions][ticker] * 10000).to_i)/ 100.0
          risk_contribution = (rd_results[:holding_vars][ticker][:proportion_var] * 10000).to_i / 100.0
          rows << [state.companies[ticker].name.three_dot_chop(20),
            ticker,
            state.companies[ticker].sector,
            shares[i].to_s,
            "#{value.to_s}",
            "#{weight.to_s}",
            "#{vol_contribution.to_s}",
            "#{(((v_results[:marginal_contributions][ticker] * 100).to_i)/100.0).to_s}",
            "#{((rd_results[:holding_vars][ticker][:individual_var] * 10000).to_i / 100.0).to_s}",
            "#{((rd_results[:holding_vars][ticker][:individual_cvar] * 10000).to_i / 100.0).to_s}",
            "#{((rd_results[:holding_vars][ticker][:marginal_var] * 10000).to_i / 100.0).to_s}",
            "#{risk_contribution.to_s}",
            "#{((cor_results[:marginal_change][ticker][:ipc] * 100).to_i / 100.0).to_s}",
            "#{((cor_results[:marginal_change][ticker][:dd_ipc] * 100).to_i / 100.0).to_s}"
          ]

          cluster_stats[cluster][:total_value] += value
          cluster_stats[cluster][:total_weight] += weight
          cluster_stats[cluster][:total_volatility] += vol_contribution
          cluster_stats[cluster][:total_risk] += risk_contribution
          cluster_stats[cluster][:color] = cluster_colors[cluster] #overwrite color...
        }
        rows << Array.new(13, "")

        cluster_stats.each_with_index { |e,i|
          k, v = e
          rows << ["Cluster #{i+1}", "", "", "", v[:total_value].to_s,
            v[:total_weight].to_s, v[:total_volatility].to_s, "", "", "", "",
            v[:total_risk].to_s, "", ""]
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

          offset = (state.dates.size - 1250) < 0 ? 0 : (state.dates.size - 1250)
          sliced_state = state.slice(offset) # 5 years

          # color_coded_correlation, ipc, filename
          results = correlation_analysis(sliced_state)

          font_size = [1, (25 / tickers.size).floor].max

          inline_renderable = "<table width=#{tickers.size*10} height=#{tickers.size*10} border=0>"
          inline_renderable += "<tr><td></td>"
          tickers.each { |t|
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t.gsub('-', '.').upcase}</b></font></td>"
          }
          inline_renderable += "<tr>"

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
          inline_renderable += "</table>"

          ipc_pct = results[:score]

          inline_renderable += "<br/><b>IPC:</b> #{100*ipc_pct}%<br/>"
          inline_renderable += "<%= image_tag '#{results[:file_name]}' %><br/>"

          inline_renderable += "<br/>"
          inline_renderable += "<table width=#{tickers.size*10} height=#{tickers.size*10} border=0>"
          inline_renderable += "<tr><td></td>"
          tickers.each { |t|
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t.gsub('-', '.').upcase}</b></font></td>"
          }
          inline_renderable += "<tr>"

          tickers.each { |t1|
            inline_renderable += "<tr>"
            inline_renderable += "<td><font size=\"#{font_size}\"><b>#{t1.gsub('-', '.').upcase}</b></font></td>"
            tickers.each { |t2|
              color = results[:dd_color_coded_correlation][t1][t2][:color]
              correlation = results[:dd_color_coded_correlation][t1][t2][:correlation]
              clamped = (correlation * 100).to_i / 100.0
              inline_renderable += "<td bgcolor=\"#{color}\"><font size=\"#{font_size}\">#{clamped}</font></td>"
            }
            inline_renderable += "</tr>"
          }
          inline_renderable += "</table>"
          
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
end