# frozen_string_literal: true

require File.expand_path('lib/chef_handler_datadog', __dir__)

Gem::Specification.new do |gem|
  gem.name             = 'chef-handler-datadog'
  gem.summary          = 'Chef Handler reports events and metrics to Datadog'
  gem.description      = 'This Handler will report the events and metrics for a chef-client run to Datadog.'
  gem.license          = 'BSD'
  gem.version          = ChefHandlerDatadog::VERSION

  gem.files            = `git ls-files`.split($\) # rubocop:disable Style/SpecialGlobalVars
  gem.executables      = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files       = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths    = ['lib']
  gem.extra_rdoc_files = ['README.md', 'LICENSE.txt']

  gem.add_dependency 'dogapi', '~> 1.44.0'

  gem.add_development_dependency 'appraisal', '~> 2.0.1'
  gem.add_development_dependency 'bundler'
  gem.add_development_dependency 'chef', '>= 12.7'
  gem.add_development_dependency 'dotenv'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'rubocop'
  gem.add_development_dependency 'simplecov'
  gem.add_development_dependency 'vcr'
  gem.add_development_dependency 'webmock'

  gem.authors       = ['Mike Fiedler', 'Adam Jacob', 'Alexis Le-Quoc']
  gem.email         = ['package@datadoghq.com']
  gem.homepage      = 'http://www.datadoghq.com/'
end
