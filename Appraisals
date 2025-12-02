# frozen_string_literal: true

# Latest release of mainline Chef versions here.
%w[12 13 14 15 16 17 18].each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', "~> #{tv}"
  end
end
