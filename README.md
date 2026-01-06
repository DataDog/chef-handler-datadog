# chef-handler-datadog

An Exception and Report Handler for Chef.

[![Gem Version](https://badge.fury.io/rb/chef-handler-datadog.svg)](http://badge.fury.io/rb/chef-handler-datadog)
[![Build Status](https://img.shields.io/circleci/build/gh/DataDog/chef-handler-datadog.svg)](https://circleci.com/gh/DataDog/chef-handler-datadog)

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

## Compatibility

This handler is tested against the following Chef Infra Client and Ruby version combinations:

| Chef Version | Supported Ruby Versions |
|--------------|-------------------------|
| Chef 12      | 2.4                     |
| Chef 13      | 2.4, 2.5                |
| Chef 14      | 2.5, 2.6                |
| Chef 15      | 2.5, 2.6, 2.7           |
| Chef 16      | 2.6, 2.7                |
| Chef 17      | 2.7, 3.0, 3.1, 3.2, 3.3 |
| Chef 18      | 3.1, 3.2, 3.3           |

**Note:** Chef Infra Client packages include their own embedded Ruby runtime. The versions listed above reflect the Ruby versions that are compatible with each Chef version. For production use, it's recommended to use the Ruby version bundled with your Chef Infra Client installation.

## Contributing to chef-handler-datadog

See [CONTRIBUTING.md](CONTRIBUTING.md)

## Copyright

Copyright (c) 2012-2025 Datadog, Inc. See LICENSE.txt for further details.

[cookbook]: https://supermarket.getchef.com/cookbooks/datadog
