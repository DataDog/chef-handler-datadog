# encoding: utf-8
require 'simplecov'
SimpleCov.start

require 'dotenv'
require 'rspec'
require 'vcr'
require 'webmock/rspec'

# Include our code
require 'chef/handler/datadog'

# Load credentials from .env
Dotenv.load

API_KEY         = ENV['API_KEY']
APPLICATION_KEY = ENV['APPLICATION_KEY']

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
end

VCR.configure do |c|
  c.cassette_library_dir = 'spec/support/cassettes'
  c.configure_rspec_metadata!
  c.default_cassette_options = {
    :record => :once,
    # :record => :new_episodes, # uncomment during development
  }

  # Remove any test-specific data
  c.before_record do |i|
    i.response.headers.delete('Set-Cookie')
    i.response.headers.delete('X-Dd-Version')
  end
  c.filter_sensitive_data('<API_KEY>') { API_KEY }
  c.filter_sensitive_data('<APPLICATION_KEY>') { APPLICATION_KEY }

  c.hook_into :webmock
end
