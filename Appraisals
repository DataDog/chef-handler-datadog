# frozen_string_literal: true

# Latest release of mainline Chef versions here.
%w[12 13 14 15 16 17 18].each do |tv|
  appraise "chef-#{tv}" do
    # Chef 16: force >= 16.5 because bundler's resolver settles on 16.0.x otherwise,
    # and chef-utils < 16.5 lacks dsl/default_paths needed by mixlib-shellout >= 3.1
    if tv == '16'
      gem 'chef', '>= 16.5', '< 17'
    else
      gem 'chef', "~> #{tv}"
    end
  end
end
