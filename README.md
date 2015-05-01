# chef-handler-datadog

An Exception and Report Handler for Chef.

[![Gem Version](https://badge.fury.io/rb/chef-handler-datadog.svg)](http://badge.fury.io/rb/chef-handler-datadog)
[![Build Status](https://travis-ci.org/DataDog/chef-handler-datadog.svg?branch=master)](https://travis-ci.org/DataDog/chef-handler-datadog)
[![Code Climate](https://codeclimate.com/github/DataDog/chef-handler-datadog/badges/gpa.svg)](https://codeclimate.com/github/DataDog/chef-handler-datadog)
[![Dependency Status](https://gemnasium.com/DataDog/chef-handler-datadog.svg)](https://gemnasium.com/DataDog/chef-handler-datadog)

## Using chef-handler-datadog

This can be installed by using the `dd-handler` recipe from the [datadog cookbook][cookbook].

```ruby
run_list 'foo::bar', 'datadog::dd-handler'
```

### Windows support

The chef handler does work on Microsoft Windows however limitations with SSL + Ruby on Windows require extra setup.  One solution is to set the `SSL_CERT_FILE` environmental variable to the one that chef uses on the machine to fix this issue. Here is how [chef](https://github.com/chef/omnibus-chef/blob/master/files/openssl-customization/windows/ssl_env_hack.rb) fixes the issue.

```ruby
# Setup the certs for ruby in windows
env 'SSL_CERT_FILE' do
  action :create
  value "C:\\opscode\\chef\\embedded\\ssl\\certs\\cacert.pem"
end
```

The Datadog Docs on [Chef](http://docs.datadoghq.com/guides/chef/#deployhandler) has detailed instructions.

## Contributing to chef-handler-datadog

See [CONTRIBUTING.md](CONTRIBUTING.md)

## Copyright

Copyright (c) 2012-2014 Datadog, Inc. See LICENSE.txt for further details.

[cookbook]: https://supermarket.getchef.com/cookbooks/datadog
