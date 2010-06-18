class CreateDataPoints < ActiveRecord::Migration
  def self.up
    create_table :data_points do |table|
      table.belongs_to :company

      table.integer   :date
      table.float     :open
      table.float     :high
      table.float     :low
      table.float     :close
      table.integer   :volume
      table.float     :adjusted_close

      table.timestamps
    end
  end

  def self.down
    drop_table :data_points
  end
end
