# encoding: utf-8

# Describe any version dependencies here.
%w(
  11.8.2
  11.10.4
  11.12.8
  11.14.2
).each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', tv
  end
end

# Due to some oddity in json gem version pinning for versions that have
# conflicts, specify best version here.
%w(
  10.26.0
  10.32.2
).each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', tv
    gem 'json', '1.7.7'
  end
end
