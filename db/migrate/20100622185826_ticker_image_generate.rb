class TickerImageGenerate < ActiveRecord::Migration
  def self.up
    add_column :companies, :image_generation_time, :date
  end

  def self.down
    remove_column :companies, :image_generation_time
  end
end
