# encoding: utf-8
require 'rubygems'
require 'chef/handler'
require 'dogapi'

class Chef
  class Handler
    # Datadog handler to send Chef run details to Datadog
    class Datadog < Chef::Handler
      attr_reader :config

      # For the tags to work, the client must have created an Application Key on the
      # "Account Settings" page here: https://app.datadoghq.com/account/settings
      # It should be passed along from the node/role/environemnt attributes, as the default is nil.
      def initialize(config = {})
        @config = config
        # If *any* api_key is not provided, this will fail immediately.
        @dog = Dogapi::Client.new(config[:api_key], config[:application_key])
      end

      def report
        # resolve correct hostname
        hostname = select_hostname(run_status.node, config)

        # Send the metrics
        emit_metrics_to_datadog(hostname, run_status)

        # Build the correct event
        event_data = build_event_data(hostname, run_status)

        # Submit the details back to Datadog
        begin
          # Send the Event data
          emit_event_to_datadog(hostname, event_data)

          # Update tags
          if config[:application_key].nil?
            Chef::Log.warn("You need an application key to let Chef tag your nodes " \
              "in Datadog. Visit https://app.datadoghq.com/account/settings#api to " \
                "create one and update your datadog attributes in the datadog cookbook."
            )
            fail ArgumentError, 'Missing Datadog Application Key'
          else
            new_host_tags = get_combined_tags(node)

            # Replace all Chef tags with the found Chef tags
            rc = @dog.update_tags(hostname, new_host_tags, 'chef')
            begin
              # See FIXME above about why I feel dirty repeating this code here
              if rc.length < 2
                Chef::Log.warn("Unexpected response from Datadog Event API: #{rc}")
              else
                if rc[0].to_i / 100 != 2
                  Chef::Log.warn("Could not submit #{new_host_tags} tags for #{hostname} to Datadog: #{rc}")
                else
                  Chef::Log.debug("Successfully updated #{hostname}'s tags to #{new_host_tags.join(', ')}")
                end
              end
            rescue
              Chef::Log.warn("Could not determine whether #{hostname}'s tags were successfully submitted to Datadog: #{rc}")
            end
          end
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
          Chef::Log.error("Could not connect to Datadog. Connection error:\n" + e)
          Chef::Log.error('Data to be submitted was:')
          Chef::Log.error(event_title)
          Chef::Log.error(event_body)
          Chef::Log.error('Tags to be set for this run:')
          Chef::Log.error(new_host_tags)
        end
      end

      private

      # Build the Event data for submission
      #
      # @param hostname [String] resolved hostname to attach to Event
      # @param run_status [Chef::RunStatus] current run status
      # @return [Array] alert_type, event_priority, event_title, event_body
      def build_event_data(hostname, run_status)
        run_time = pluralize(run_status.elapsed_time, 'second')

        # This is the first line of the Event body, the rest is appended here.
        event_body = "Chef updated #{run_status.updated_resources.length} resources out of #{run_status.all_resources.length} resources total."

        if run_status.success?
          alert_type = 'success'
          event_priority = 'low'
          event_title = "Chef completed in #{run_time} on #{hostname} "
        else
          alert_type = 'error'
          event_priority = 'normal'
          event_title = "Chef failed in #{run_time} on #{hostname} "

          if @config[:notify_on_failure]
            handles = @config[:notify_on_failure]
            # convert the notification handle array to a string
            event_body << "\nAlerting: #{handles.join(' ')}\n"
          end

          event_body << "\n@@@\n#{run_status.formatted_exception}\n@@@\n"
          event_body << "\n@@@\n#{run_status.backtrace.join("\n")}\n@@@\n"
        end

        if run_status.updated_resources.length.to_i > 0
          event_body << "\n@@@\n"
          run_status.updated_resources.each do |r|
            event_body << "- #{r} (#{r.defined_at})\n"
          end
          event_body << "\n@@@\n"
        end

        # Return resolved data
        [alert_type, event_priority, event_title, event_body]
      end

      # Emit Event to Datadog Event Stream
      #
      # @param hostname [String] resolved hostname to attach to Event
      # @param event_params [Array] all the configurables to build a valid Event
      def emit_event_to_datadog(hostname, event_data)
        alert_type, event_priority, event_title, event_body = event_data

        evt = @dog.emit_event(Dogapi::Event.new(event_body,
                                                :msg_title => event_title,
                                                :event_type => 'config_management.run',
                                                :event_object => hostname,
                                                :alert_type => alert_type,
                                                :priority => event_priority,
                                                :source_type_name => 'chef'
        ), :host => hostname)

        begin
          # FIXME: nice-to-have: abstract format of return value away a bit
          # in dogapi directly. See https://github.com/DataDog/dogapi-rb/issues/18
          if evt.length < 2
            Chef::Log.warn("Unexpected response from Datadog Event API: #{evt}")
          else
            # [http_response_code, {"event" => {"url" => "...", ...}}]
            # 2xx means ok
            if evt[0].to_i / 100 != 2
              Chef::Log.warn("Could not submit event to Datadog (HTTP call failed): #{evt[0]}")
            else
              Chef::Log.debug("Successfully submitted Chef event to Datadog for #{hostname} at #{evt[1]['event']['url']}")
            end
          end
        rescue
          Chef::Log.warn("Could not determine whether chef run was successfully submitted to Datadog: #{evt}")
        end
      end

      # Emit Chef metrics to Datadog
      #
      # @param hostname [String] resolved hostname to attach to series
      # @param run_status [Chef::RunStatus] current run status
      def emit_metrics_to_datadog(hostname, run_status)
        @dog.emit_point('chef.resources.total', run_status.all_resources.length, :host => hostname)
        @dog.emit_point('chef.resources.updated', run_status.updated_resources.length, :host => hostname)
        @dog.emit_point('chef.resources.elapsed_time', run_status.elapsed_time, :host => hostname)
        Chef::Log.debug('Submitted Chef metrics back to Datadog')
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
      end

      # Build up an array of Chef tags to send back
      #
      # Selects all [env, roles, tags] from the Node's object and reformats
      # them to `key:value` e.g. `role:database-master`.
      #
      # @param node [Chef::Node]
      # @return [Array] current Chef env, roles, tags
      def get_combined_tags(node)
        chef_env = get_node_env(node).split # converts a string into an array

        chef_roles = get_node_roles(node)
        chef_tags = get_node_tags(node)

        # Combine (union) all arrays. Removes duplicates if found.
        chef_env | chef_roles | chef_tags
      end

      def get_node_roles(node)
        node.run_list.roles.map! { |role| 'role:' + role }
      end

      def get_node_env(node)
        'env:' + node.chef_environment if node.respond_to?('chef_environment')
      end

      def get_node_tags(node)
        node.tags.map! { |tag| 'tag:' + tag }
      end

      def pluralize(number, noun)
        case number
        when 0..1
          "less than 1 #{noun}"
        else
          "#{number.round} #{noun}s"
        end
      rescue
        Chef::Log.warn("Cannot make #{number} more legible")
        "#{number} #{noun}s"
      end

      # Select which hostname to report back to Datadog.
      # Makes decision based on inputs from `config` and when absent, use the
      # node's `ec2` attribute existence to make the decision.
      #
      # @param node [Chef::Node] from `run_status`, can feasibly any `node`
      # @param config [Hash] config object passed in to handler
      # @return [String] the hostname decided upon
      def select_hostname(node, config)
        use_ec2_instance_id = !config.key?(:use_ec2_instance_id) ||
                                (config.key?(:use_ec2_instance_id) &&
                                  config[:use_ec2_instance_id])

        if config[:hostname]
          config[:hostname]
        elsif use_ec2_instance_id && node.attribute?('ec2') && node.ec2.attribute?('instance_id')
          node.ec2.instance_id
        else
          node.name
        end
      end
    end # end class Datadog
  end # end class Handler
end # end class Chef
