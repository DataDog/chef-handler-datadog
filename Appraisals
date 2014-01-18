# encoding: utf-8

# Describe any version dependencies here.

test_versions_chef = %w(
  10.14.0
  10.30.2
  11.8.2
)

test_versions_chef.each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', tv
  end
end

# Due to some oddity in json gem version pinning for 10.26.0
appraise 'chef-10.26.0' do
  gem 'chef', '10.26.0'
  gem 'json', '1.7.7'
end
