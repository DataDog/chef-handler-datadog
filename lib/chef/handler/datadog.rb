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
        @dog = Dogapi::Client.new(@config[:api_key], @config[:application_key])
      end

      def report
        # use agent proxy settings if available
        use_agent_proxy unless ENV['DATADOG_PROXY'].nil?

        hostname = resolve_correct_hostname(run_status.node, config)

        # Send the metrics
        metrics =
            DatadogChefMetrics.new
            .with_dogapi_client(@dog)
            .for_hostname(hostname)
            .using_run_status(run_status)

        # Collect tags
        tags =
            DatadogChefTags.new
            .with_dogapi_client(@dog)
            .for_hostname(hostname)
            .for_node(node)
            .with_application_key(@config[:application_key])

        # Build the event
        event =
            DatadogChefEvents.new
            .with_dogapi_client(@dog)
            .for_hostname(hostname)
            .using_run_status(run_status)
            .with_failure_notifications(@config['notify_on_failure'])
            .with_tags(tags.combined_host_tags)

        # Submit the details back to Datadog
        begin
          metrics.emit_to_datadog
          event.emit_to_datadog
          tags.update_to_datadog
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
          Chef::Log.error("Could not connect to Datadog. Connection error:\n" + e)
          Chef::Log.error('Data to be submitted was:')
          Chef::Log.error(event.event_title)
          Chef::Log.error(event.event_body)
          Chef::Log.error('Tags to be set for this run:')
          Chef::Log.error(tags.combined_host_tags)
        end
      ensure
        # restore the env proxy settings before leaving
        restore_env_proxies unless ENV['DATADOG_PROXY'].nil?
      end

      private

      # Select which hostname to report back to Datadog.
      # Makes decision based on inputs from `config` and when absent, use the
      # node's `ec2` attribute existence to make the decision.
      #
      # @param node [Chef::Node] from `run_status`, can feasibly any `node`
      # @param config [Hash] config object passed in to handler
      # @return [String] the hostname decided upon
      def resolve_correct_hostname(node, config)
        use_ec2_instance_id = !config.key?(:use_ec2_instance_id) ||
                              (config.key?(:use_ec2_instance_id) && config[:use_ec2_instance_id])

        if config[:hostname]
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
    end # end class Datadog
  end # end class Handler
end # end class Chef
