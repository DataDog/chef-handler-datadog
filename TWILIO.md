# chef-handler-datadog (Twilio Edition)

## Using chef-handler-datadog

Method below are utilizing the `run_action(:enable)` functionality to enable the gem and the reporter to run in the compile phase of the Chef run.

This can be installed by using the chef_metrics::datadog_reporter recipe

It is automatically added to the run_list via [chef_provision.py](https://code.hq.twilio.comtwilio/chef-bootstrap/blob/master/chef_provision.py#L239)


## Updating the version of Gem


* make changes to the code, test, verify and merge
* update the version of the gem!
 ```gem
build chef-handler-datadog.gemspec
```
* copy to `chef-metrics/files/default` directory
* update `chef-metrics/recipes/datadog_reporter.rb` with the appropriate version
* verify chef-metrics, test, deploy