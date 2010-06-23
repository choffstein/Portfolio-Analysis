class CompanyLastUpdate < ActiveRecord::Migration
  def self.up
    add_column :companies, :last_update, :date
  end

  def self.down
    remove_column :companies, :last_update
  end
end
