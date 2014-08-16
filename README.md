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

The Datadog Docs on [Chef](http://docs.datadoghq.com/guides/chef/#deployhandler) has detailed instructions.

## Contributing to chef-handler-datadog

See [CONTRIBUTING.md](CONTRIBUTING.md)

## Copyright

Copyright (c) 2012-2014 Datadog, Inc. See LICENSE.txt for further details.

[cookbook]: https://supermarket.getchef.com/cookbooks/datadog
