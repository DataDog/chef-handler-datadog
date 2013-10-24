require File.expand_path('../lib/chef-handler-datadog', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "chef-handler-datadog"
  gem.summary       = %q{Chef Handler for DataDog events and metrics}
  gem.description   = %q{This Handler will report the events and metrics for a chef-client run to DataDog.}
  gem.license       = "BSD"
  gem.version       = ChefHandlerDatadog::VERSION

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.extra_rdoc_files = ['README.md', 'LICENSE.txt']

  gem.add_dependency 'dogapi', ">= 1.2"

  gem.add_development_dependency 'chef', ">= 10", "<= 12"
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'bundler'
  gem.add_development_dependency 'travis-lint'
  gem.add_development_dependency 'tailor', '~> 1.3'

  gem.authors       = ["Mike Fiedler", "Adam Jacob", "Alexis Le-Quoc"]
  gem.email         = ["package@datadoghq.com"]
  gem.homepage      = "http://www.datadoghq.com/"
end
