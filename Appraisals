# frozen_string_literal: true

# Latest release of mainline Chef versions here.
%w[12 13 14 15 16 17 18].each do |tv|
  appraise "chef-#{tv}" do
    # Chef 16 requires >= 16.5 because chef-utils < 16.5 lacks dsl/default_paths
    # which is needed by mixlib-shellout >= 3.1 (required by ohai 16.x)
    if tv == '16'
      gem 'chef', '>= 16.5', '< 17'
    else
      gem 'chef', "~> #{tv}"
    end
  end
end
