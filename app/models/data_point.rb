class DataPoint < ActiveRecord::Base
    belongs_to :company

    # this is very, very slow
    #validates_uniqueness_of :date, :scope => :company_id

  def to_s
    "Date: #{Time.at(self.date)} Open: #{self.open} High: #{self.high} Low: #{self.low} Close: #{self.close} Volume: #{self.volume} Adjusted Close: #{self.adjusted_close}"
  end
end