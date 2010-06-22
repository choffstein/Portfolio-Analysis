class DataPointsMultiColumnIndex < ActiveRecord::Migration
  def self.up
    add_index :data_points, [:date, :company_id], :unique => true
  end

  def self.down
    remove_index :data_points, [:data, :company_id]
  end
end
