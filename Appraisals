# encoding: utf-8

# Describe any version dependencies here.

%w(
  10.14.0
  10.30.2
).each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', tv
  end
end

# Due to some oddity in json gem version pinning for versions that have
# conflicts, specify best version here.
%w(
  10.26.0
  11.8.2
).each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', tv
    gem 'json', '1.7.7'
  end
end
