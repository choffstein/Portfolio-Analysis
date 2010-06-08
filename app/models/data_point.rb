class DataPoint < ActiveRecord::Base
    belongs_to :company

    # this is very, very slow
    validates_uniqueness_of :date, :scope => :company_id
end