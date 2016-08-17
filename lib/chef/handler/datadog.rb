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

        # If *any* api_key is not provided, this will fail immediately.
        @dog = Dogapi::Client.new(
          @config[:api_key],
          @config[:application_key],
          nil,   # host
          nil,   # device
          true,  # silent
          nil,   # timeout
          extra_endpoints
        )
      end

      def report
        # use datadog agent proxy settings, if available
        use_agent_proxy unless ENV['DATADOG_PROXY'].nil?

        # prepare the metrics, event, and tags information to be reported
        prepare_report_for_datadog
        # post the report information to the datadog service
        send_report_to_datadog
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
            .with_dogapi_client(@dog)
            .with_hostname(hostname)
            .with_run_status(run_status)

        # Collect and prepare tags
        @tags =
            DatadogChefTags.new
            .with_dogapi_client(@dog)
            .with_hostname(hostname)
            .with_run_status(run_status)
            .with_application_key(config[:application_key])
            .with_tag_prefix(config[:tag_prefix])
            .with_retries(config[:tags_submission_retries])
            .with_tag_blacklist(config[:tags_blacklist_regex])
            .with_scope_prefix(config[:scope_prefix])

        # Build the chef event information
        @event =
            DatadogChefEvents.new
            .with_dogapi_client(@dog)
            .with_hostname(hostname)
            .with_run_status(run_status)
            .with_failure_notifications(@config['notify_on_failure'])
            .with_tags(@tags.combined_host_tags)
      end

      # Submit metrics, event, and tags information to datadog
      def send_report_to_datadog
        @metrics.emit_to_datadog
        @event.emit_to_datadog
        @tags.send_update_to_datadog
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        Chef::Log.error("Could not connect to Datadog. Connection error:\n" + e)
        Chef::Log.error('Data to be submitted was:')
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
          puts "found hostname #{config[:hostname]} in config object"
          config[:hostname]
        elsif use_ec2_instance_id && node.attribute?('ec2') && node.ec2.attribute?('instance_id')
          node.ec2.instance_id
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

      def extra_endpoints
        urls = @config[:other_dd_urls]
        api_keys = @config[:other_api_keys]
        app_keys = @config[:other_application_keys]

        return nil unless validate_extra_endpoints(urls, api_keys, app_keys)

        if urls.nil?
          keys = []
          api_keys.each_with_index do |api_key, index|
            keys.push([api_key, app_keys[index]])
          end
          return keys
        else
          endpoints = Hash.new []
          urls.each_with_index do |url, index|
            endpoints[url] = endpoints[url] + [[api_keys[index], app_keys[index]]]
          end
          return endpoints
        end
      end

      def validate_extra_endpoints(urls, api_keys, app_keys)
        return false if api_keys.nil?
        # If not enough app_keys compared to api_keys
        if app_keys.nil? || app_keys.length != api_keys.length
          Chef::Log.error('Bad number of other_application_keys given:')
          Chef::Log.error("#{api_keys.length} other_api_keys, " \
                          "#{app_keys.nil? ? 0 : app_keys.length} other_application_keys")
          return false
        end
        # If not enough api_keys compared to dd_urls
        if !urls.nil? && urls.length != api_keys.length
          Chef::Log.error('Bad number of other_api_keys given:')
          Chef::Log.error("#{urls.length} other_dd_urls, " \
                        "#{api_keys.length} other_api_keys")
          return false
        end
        true
      end
    end # end class Datadog
  end # end class Handler
end # end class Chef
