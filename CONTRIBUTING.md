# Contributing

If you'd like to run the test suite, fix a bug or add a feature, please follow these steps:

* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it
* Check out the latest `master` branch to make sure the feature hasn't been implemented or the bug hasn't been fixed
* Fork the project
* Install all dependencies: `bundle install`
* Start a feature/bugfix branch: `git checkout -b my_feature_name`
* Place a `.env` file in the root of the project with `API_KEY` and `APPLICATION_KEY`:

        API_KEY: myapikey
        APPLICATION_KEY: chefhandlerspecificapplicationkey

  This file is intentionally .gitignored to prevent security exposure.
  You may use your own Datadog account keys, as the keys are filtered from the test recordings.
  Running the test suite will _not_ make calls to Datadog for existing tests, see `spec/support/cassettes/` for more.

* Run `rake` to execute tests, ensure they pass
* Commit and push until you are happy with your contribution
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the `Rakefile`, version, or history.
  If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.
