# encoding: utf-8
require 'rubygems'
require 'chef/handler'
require 'chef/mash'
require 'dogapi'
require_relative 'datadog_chef_metrics'
require_relative 'datadog_chef_tags'
require_relative 'datadog_chef_events'

class Chef
  class Handler
    # Datadog handler to send Chef run details to Datadog
    class Datadog < Chef::Handler
      attr_reader :config

      # For the tags to work, the client must have created an Application Key on the
      # "Account Settings" page here: https://app.datadoghq.com/account/settings
      # It should be passed along from the node/role/environemnt attributes, as the default is nil.
      def initialize(config = {})
        @config = Mash.new(config)

        @dogs = prepare_the_pack
      end

      def report
        # use datadog agent proxy settings, if available
        use_agent_proxy unless ENV['DATADOG_PROXY'].nil?

        # prepare the metrics, event, and tags information to be reported
        prepare_report_for_datadog

        @dogs.each do |dog|
          # post the report information to the datadog service
          Chef::Log.debug("Sending Chef report to #{dog.datadog_host}")
          send_report_to_datadog dog
        end
      ensure
        # restore the env proxy settings before leaving to avoid downstream side-effects
        restore_env_proxies unless ENV['DATADOG_PROXY'].nil?
      end

      private

      # prepare metrics, event, and tags data for posting to datadog
      def prepare_report_for_datadog
        # uses class method accessors for run_status and config
        hostname = resolve_correct_hostname
        # prepare chef run metrics
        @metrics =
            DatadogChefMetrics.new
            .with_hostname(hostname)
            .with_run_status(run_status)

        # Collect and prepare tags
        @tags =
            DatadogChefTags.new
            .with_hostname(hostname)
            .with_run_status(run_status)
            .with_tag_prefix(config[:tag_prefix])
            .with_retries(config[:tags_submission_retries])
            .with_tag_blacklist(config[:tags_blacklist_regex])
            .with_scope_prefix(config[:scope_prefix])
            .with_policy_tags_enabled(config[:send_policy_tags])

        # Build the chef event information
        @event =
            DatadogChefEvents.new
            .with_hostname(hostname)
            .with_run_status(run_status)
            .with_failure_notifications(@config['notify_on_failure'])
            .with_tags(@tags.combined_host_tags)
      end

      # Submit metrics, event, and tags information to datadog
      #
      # @param dog [Dogapi::Client] Dogapi Client to be used
      def send_report_to_datadog(dog)
        @metrics.emit_to_datadog dog
        @event.emit_to_datadog dog
        @tags.send_update_to_datadog dog
      rescue => e
        Chef::Log.error("Could not send/emit to Datadog:\n" + e.to_s)
        Chef::Log.error('Event data to be submitted was:')
        Chef::Log.error(@event.event_title)
        Chef::Log.error(@event.event_body)
        Chef::Log.error('Tags to be set for this run:')
        Chef::Log.error(@tags.combined_host_tags)
      end

      # Select which hostname to report back to Datadog.
      # Makes decision based on inputs from `config` and when absent, use the
      # node's `ec2` attribute existence to make the decision.
      #
      # @return [String] the hostname decided upon
      def resolve_correct_hostname
        node = run_status.node
        use_ec2_instance_id = !config.key?(:use_ec2_instance_id) ||
                              (config.key?(:use_ec2_instance_id) && config[:use_ec2_instance_id])

        if config[:hostname]
          config[:hostname]
        elsif use_ec2_instance_id && node.attribute?('ec2') && node['ec2'].attribute?('instance_id')
          node['ec2']['instance_id']
        else
          node.name
        end
      end

      # Using the agent proxy settings requires setting http(s)_proxy
      # env vars.  However, original env var settings need to be
      # preserved for restoration at the end of the handler.
      def use_agent_proxy
        Chef::Log.info('Using agent proxy settings')
        @env_http_proxy = ENV['http_proxy']
        @env_https_proxy = ENV['https_proxy']
        ENV['http_proxy'] = ENV['DATADOG_PROXY']
        ENV['https_proxy'] = ENV['DATADOG_PROXY']
      end

      # Restore environment proxy settings to pre-report values
      def restore_env_proxies
        ENV['http_proxy'] = @env_http_proxy
        ENV['https_proxy'] = @env_https_proxy
      end

      # create and configure all the Dogapi Clients to be used
      #
      # @return [Array] all Dogapi::Client to be used
      def prepare_the_pack
        dogs = []
        endpoints.each do |url, api_key, app_key|
          begin
            dogs.push(Dogapi::Client.new(
                        api_key,
                        app_key,
                        nil,   # host
                        nil,   # device
                        false, # silent
                        nil,   # timeout
                        url,
                        config[:skip_ssl_validation]
            ))
          rescue => e
            Chef::Log.error("Could not create API Client '#{url}'\n #{e.to_s}")
          end
        end
        dogs
      end

      def config_url()
        url = 'https://app.datadoghq.com'
        url = 'https://app.' + @config[:site] unless @config[:site].nil?
        url = @config[:url] unless @config[:url].nil?
        url
      end

      # return all endpoints as a list of triplets [url, api_key, application_key]
      def endpoints
        validate_keys(@config[:api_key], @config[:application_key], true)

        # the first endpoint is always the url/site + apikey + appkey one
        endpoints = [[config_url(), @config[:api_key], @config[:application_key]]]

        # then add extra endpoints
        extra_endpoints = @config[:extra_endpoints] || []
        extra_endpoints.each do |endpoint|
          url = endpoint[:api_url] || endpoint[:url] || config_url()
          api_key = endpoint[:api_key]
          app_key = endpoint[:application_key]
          endpoints << [url, api_key, app_key] if validate_keys(api_key, app_key, false)
        end

        endpoints
      end

      # Validate endpoints config (api_key and application key)
      # fails if incorrect and should_fail is true (needed for the default)
      # Doesn't fail for the other endpoints but logs a warning
      def validate_keys(api_key, app_key, should_fail)
        if api_key.nil?
          Chef::Log.warn('You need an API key to communicate with Datadog')
          fail ArgumentError, 'Missing Datadog Api Key' if should_fail
          return false
        end
        if app_key.nil?
          Chef::Log.warn('You need an application key to let Chef tag your nodes ' \
                         'in Datadog. Visit https://app.datadoghq.com/account/settings#api to ' \
                         'create one and update your datadog attributes in the datadog cookbook.')
          fail ArgumentError, 'Missing Datadog Application Key' if should_fail
          return false
        end
        true
      end
    end # end class Datadog
  end # end class Handler
end # end class Chef
