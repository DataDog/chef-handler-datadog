# frozen_string_literal: true

source 'http://rubygems.org'

# Specify your gem's dependencies in chef-handler-datadog.gemspec
gemspec

group :localdev do
  gem 'chef', "~> #{ENV.fetch('CHEF_VERSION', '15.0')}"
  gem 'guard'
  gem 'guard-rspec'
  gem 'guard-rubocop'
  gem 'pry'
  gem 'terminal-notifier-guard'
  gem 'travis-lint'
end
