# Latest release of mainline Chef versions here.
%w[12 13 14].each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', "~> #{tv}.0"
  end
end

appraise 'chef-12.7' do
  gem 'chef', '~> 12.7'
end
