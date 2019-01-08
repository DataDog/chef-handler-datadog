# Latest release of mainline Chef versions here.
%w[10 12].each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', "~> #{tv}.0"
  end
end

# Describe any specific Chef versions here.
appraise 'chef-10.14.4' do
  gem 'chef', '10.14.4'
  # Old versions of Chef didn't pin the max version of Ohai they supported.
  # See: http://git.io/vecAn
  gem 'ohai', '< 8.0'
end

appraise 'chef-11' do
  gem 'chef', '~> 11.0'
  # for some reason bundler installs json 2.x and rack 2.x even when they don't support the version of
  # ruby installed, so let's force compatible versions here
  gem 'json', '< 2.0'
  gem 'rack', '< 2.0'
end
