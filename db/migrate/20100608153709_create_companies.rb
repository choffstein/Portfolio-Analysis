class CreateCompanies < ActiveRecord::Migration
  def self.up
    create_table :companies do |table|
      table.string    :ticker
      table.string    :name
      table.string    :sector
      table.string    :industry
      table.text      :profile

      table.timestamps
    end
  end

  def self.down
    drop_table :companies
  end
end
