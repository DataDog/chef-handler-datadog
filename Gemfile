# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in chef-handler-datadog.gemspec
gemspec

# Only include chef directly when not running under Appraisal
# (Appraisal manages the chef version via generated gemfiles)
unless ENV['APPRAISAL_INITIALIZED']
  chef_version = ENV.fetch('CHEF_VERSION', '18.0').to_f
  gem 'chef', "~> #{chef_version}"
  # mixlib-shellout >= 3.2 requires chef-utils/dsl/default_paths which doesn't exist in chef-utils bundled with Chef < 16.5
  gem 'mixlib-shellout', '< 3.2' if chef_version < 17.0
end

group :localdev do
  gem 'guard'
  gem 'guard-rspec'
  gem 'pry'
  gem 'terminal-notifier-guard'
  gem 'travis-lint'
end
