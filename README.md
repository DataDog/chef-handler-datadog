# chef-handler-datadog

An Exception and Report Handler for Chef.

[![Gem Version](https://badge.fury.io/rb/chef-handler-datadog.png)](http://badge.fury.io/rb/chef-handler-datadog)
[![Build Status](https://secure.travis-ci.org/DataDog/chef-handler-datadog.png?branch=master)](http://travis-ci.org/DataDog/chef-handler-datadog)
[![Code Climate](https://codeclimate.com/github/DataDog/chef-handler-datadog.png)](https://codeclimate.com/github/DataDog/chef-handler-datadog)
[![Dependency Status](https://gemnasium.com/DataDog/chef-handler-datadog.png)](https://gemnasium.com/DataDog/chef-handler-datadog)

## Using chef-handler-datadog

The Datadog Docs on [Chef](http://docs.datadoghq.com/guides/chef/#deployhandler) has detailed instructions.

## Contributing to chef-handler-datadog

* Check out the latest `master` to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it
* Fork the project
* Start a feature/bugfix branch
* Place a `.env` file in the root of the project with `API_KEY` and `APPLICATION_KEY`:

        API_KEY: myapikey
        APPLICATION_KEY: chefhandlerspecificapplicationkey

  This file is intentionally .gitignored to prevent security exposure.

* Run `rake` to execute tests, ensure they pass
* Commit and push until you are happy with your contribution
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the `Rakefile`, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2012-2014 Datadog, Inc. See LICENSE.txt for further details.

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/DataDog/chef-handler-datadog/trend.png)](https://bitdeli.com/free "Bitdeli Badge")
