# encoding: utf-8

# Latest release of mainline Chef versions here.
%w(10 11 12).each do |tv|
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
