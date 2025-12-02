# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in chef-handler-datadog.gemspec
gemspec

# Only include chef directly when not running under Appraisal
# (Appraisal manages the chef version via generated gemfiles)
unless ENV['APPRAISAL_INITIALIZED']
  chef_version = ENV.fetch('CHEF_VERSION', '18.0').to_f
  gem 'chef', "~> #{chef_version}"
  # mixlib-shellout >= 3.3 requires chef-utils which has compatibility issues with Chef < 17
  gem 'mixlib-shellout', '< 3.3' if chef_version < 17.0
end

group :localdev do
  gem 'guard'
  gem 'guard-rspec'
  gem 'pry'
  gem 'terminal-notifier-guard'
  gem 'travis-lint'
end
