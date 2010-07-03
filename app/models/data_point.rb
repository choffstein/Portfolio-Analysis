class DataPoint
  attr_reader :date, :open, :high, :low, :close, :volume, :adjusted_close

  def initialize(params)
    params.each { |k, v|
      instance_variable_set("@#{k}",v)
    }
  end

  def to_s
    "Date: #{Time.at(@date)} Open: #{@open} High: #{@high} Low: #{@low} Close: #{@close} Volume: #{@volume} Adjusted Close: #{@adjusted_close}"
  end
end