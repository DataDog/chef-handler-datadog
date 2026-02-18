# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in chef-handler-datadog.gemspec
gemspec

# Only include chef directly when not running under Appraisal
# (Appraisal manages the chef version via generated gemfiles)
unless ENV['APPRAISAL_INITIALIZED']
  chef_version = ENV.fetch('CHEF_VERSION', '18.0')

  # Chef 16: force >= 16.5 because bundler's resolver settles on 16.0.x otherwise,
  # and chef-utils < 16.5 lacks dsl/default_paths needed by mixlib-shellout >= 3.1
  if chef_version.start_with?('16')
    gem 'chef', '>= 16.5', '< 17'
  else
    gem 'chef', "~> #{chef_version}"
  end

  # mixlib-shellout >= 3.1 requires chef-utils/dsl/default_paths which doesn't exist in chef-utils bundled with Chef < 16
  gem 'mixlib-shellout', '< 3.1' if Gem::Version.new(chef_version) < Gem::Version.new('16.0')
end

group :localdev do
  gem 'guard'
  gem 'guard-rspec'
  gem 'pry'
  gem 'terminal-notifier-guard'
  gem 'travis-lint'
end
