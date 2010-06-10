module Yahoo
  module YQL
    def self.get_company_name(ticker)
      url = "\"http://finance.yahoo.com/q/pr?s=#{ticker}\""
      query = "select * from html where url=#{url} and xpath='//td[@class=\"yfnc_modtitlew2\"]'"
      results = yql_query(query)
      begin
        company_name = clean_result(results['query']['results']['td'][0]['strong'])
        company_name.gsub!(',', '') #get rid of extraneous commas
      rescue
      end
      return company_name
    end

    def self.get_company_profile(ticker)
      url = "\"http://finance.yahoo.com/q/pr?s=#{ticker}\""
      query = "select * from html where url=#{url} and xpath='//table[@id=\"yfncsumtab\"][1]//table[4]'"
      begin
        results = yql_query(query)
        company_profile = clean_result(results['query']['results']['table'][0]['tr'][0]['td']['p'])
      rescue
      end
      return company_profile
    end

    def self.get_company_sector(ticker)
      url = "\"http://finance.yahoo.com/q/pr?s=#{ticker}\""
      query = "select * from html where url=#{url} and xpath='//table[@class=\"yfnc_datamodoutline1\"][1]/tr/td/table/tr'"
      begin
        results = yql_query(query)
        sector = clean_result(results['query']['results']['tr'][1]['td'][1]['a']['content'])
      rescue
      end
      return sector
    end


    private
    MAX_QUERIES = 10

    def self.clean_result(r)
      r.strip.gsub(/[\n]+/, " ").gsub(/[\r]+/, " ").squeeze(" ")
    end

    def self.yql_query(query)
      uri = "http://query.yahooapis.com/v1/public/yql"

      tries = 0
      begin
        # everything's requested via POST, which is all I needed when I wrote this
        # likewise, everything coming back is json encoded
        response = Net::HTTP.post_form( URI.parse( uri ), {
            'q' => query,
            'format' => 'json'
          } )

        json = JSON.parse( response.body )
      rescue
        if tries < MAX_QUERIES
          tries = tries + 1
          sleep(tries)
          retry
        else
          raise
        end
      end

      return json
    end
  end
end