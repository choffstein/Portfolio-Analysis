# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20100622194250) do

  create_table "companies", :force => true do |t|
    t.string   "ticker"
    t.string   "name"
    t.string   "sector"
    t.string   "industry"
    t.text     "profile"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.date     "image_generation_time"
    t.date     "last_update"
  end

  create_table "data_points", :force => true do |t|
    t.integer  "company_id"
    t.integer  "date"
    t.float    "open"
    t.float    "high"
    t.float    "low"
    t.float    "close"
    t.integer  "volume"
    t.float    "adjusted_close"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "data_points", ["date", "company_id"], :name => "index_data_points_on_date_and_company_id", :unique => true

end
