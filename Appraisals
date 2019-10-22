# frozen_string_literal: true

# Latest release of mainline Chef versions here.
%w[12 12.7 13 14].each do |tv|
  appraise "chef-#{tv}" do
    gem 'chef', "~> #{tv}"
  end
end
