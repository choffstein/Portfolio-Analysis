# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_Portfolio Analysis_session',
  :secret      => 'faa67dc7e85a8c7d7efcd29856a16ec59aef426a3b26326e7e10d04148ae73082ebb68dc0879908f0afdb3cbf4e0c2f18ca4664213e352138ff8fff5379e184a'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
