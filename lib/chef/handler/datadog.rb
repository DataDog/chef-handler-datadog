require 'rubygems'
require 'chef'
require 'chef/handler'
require 'dogapi'

class Chef
  class Handler
    class Datadog < Chef::Handler

      # For the tags to work, the client must have created an Application Key on the
      # "Account Settings" page here: https://app.datadoghq.com/account/settings
      # It should be passed along from the node/role/environemnt attributes, as the default is nil.
      def initialize(opts = nil)
        opts = opts || {}
        @api_key = opts[:api_key]
        @application_key = opts[:application_key]
        # If we're on ec2, use the instance by default, unless instructed otherwise
        @use_ec2_instance_id = !opts.has_key?(:use_ec2_instance_id) || opts.has_key?(:use_ec2_instance_id) && opts[:use_ec2_instance_id]
        @dog = Dogapi::Client.new(@api_key, application_key = @application_key)
      end

      def report
        hostname = run_status.node.name
        if @use_ec2_instance_id && run_status.node.attribute?("ec2") && run_status.node.ec2.attribute?("instance_id")
          hostname = run_status.node.ec2.instance_id
        end

        # Send the metrics
        begin
          @dog.emit_point("chef.resources.total", run_status.all_resources.length, :host => hostname)
          @dog.emit_point("chef.resources.updated", run_status.updated_resources.length, :host => hostname)
          @dog.emit_point("chef.resources.elapsed_time", run_status.elapsed_time, :host => hostname)
          Chef::Log.debug("Submitted chef metrics back to Datadog")
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
          Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
        end

        event_title = ""
        run_time = pluralize(run_status.elapsed_time, "second")
        if run_status.success?
          alert_type = "success"
          event_priority = "low"
          event_title << "Chef completed in #{run_time} on #{hostname} "
        else
          event_title << "Chef failed in #{run_time} on #{hostname} "
        end

        event_data = "Chef updated #{run_status.updated_resources.length} resources out of #{run_status.all_resources.length} resources total."
        if run_status.updated_resources.length.to_i > 0
          event_data << "\n@@@\n"
          run_status.updated_resources.each do |r|
            event_data << "- #{r.to_s} (#{defined_at(r)})\n"
          end
          event_data << "\n@@@\n"
        end

        if run_status.failed?
          alert_type = "error"
          event_priority = "normal"
          event_data << "\n@@@\n#{run_status.formatted_exception}\n@@@\n"
          event_data << "\n@@@\n#{run_status.backtrace.join("\n")}\n@@@\n"
        end

        # Submit the details back to Datadog
        begin
          # Send the Event data
          evt = @dog.emit_event(Dogapi::Event.new(event_data,
                                                  :msg_title => event_title,
                                                  :event_type => 'config_management.run',
                                                  :event_object => hostname,
                                                  :alert_type => alert_type,
                                                  :priority => event_priority,
                                                  :source_type_name => 'chef'
                                                  ), :host => hostname)
          begin
            # FIXME nice-to-have: abstract format of return value away a bit
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

          # Get the current list of tags, remove any "role:" entries
          host_tags = @dog.host_tags(hostname)[1]["tags"] || []
          host_tags.delete_if { |tag| tag.start_with?('role:') }

          # Get list of chef roles, rename them to tag format
          chef_roles = node.run_list.roles
          chef_roles.collect! { |role| "role:" + role }

          # Get the chef environment (as long as it's not '_default')
          if node.respond_to?('chef_environment') && node.chef_environment != '_default'
            host_tags.delete_if { |tag| tag.start_with?('env:') }
            host_tags << "env:" + node.chef_environment
          end

          # Combine (union) both arrays. Removes dupes, preserves non-chef tags.
          new_host_tags = host_tags | chef_roles

          if @application_key.nil?
            Chef::Log.warn("You need an application key to let Chef tag your nodes " \
              "in Datadog. Visit https://app.datadoghq.com/account/settings#api to " \
              "create one and update your datadog attributes in the datadog cookbook."
            )
          else
            # Replace all tags with the new tags
            rc = @dog.update_tags(hostname, new_host_tags)
            begin
              # See FIXME above about why I feel dirty repeating this code here
              if rc.length < 2
                Chef::Log.warn("Unexpected response from Datadog Event API: #{evt}")
              else
                if rc[0].to_i / 100 != 2
                  Chef::Log.warn("Could not submit #{chef_roles} tags for #{hostname} to Datadog")
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
          Chef::Log.error("Data to be submitted was:")
          Chef::Log.error(event_title)
          Chef::Log.error(event_data)
          Chef::Log.error("Tags to be set for this run:")
          Chef::Log.error(new_host_tags)
        end
      end

      private

      def pluralize(number, noun)
        begin
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
      end

    ## This function is to mimic behavior built into a later version of chef than 0.9.x
    ## Source is here: https://github.com/opscode/chef/blob/master/chef/lib/chef/resource.rb#L415-424
    ## Including this based on help from schisamo
      def defined_at(resource)
        cookbook_name = resource.cookbook_name
        recipe_name = resource.recipe_name
        source_line = resource.source_line
        if cookbook_name && recipe_name && source_line
          "#{cookbook_name}::#{recipe_name} line #{source_line.split(':')[1]}"
        elsif source_line
          file, line_no = source_line.split(':')
          "#{file} line #{line_no}"
        else
          "dynamically defined"
        end
      end

    end #end class Datadog
  end #end class Handler
end #end class Chef
