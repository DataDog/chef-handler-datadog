require 'rubygems'
require 'chef'
require 'chef/handler'
require 'dogapi'

class Datadog < Chef::Handler
  
  # For the tags to work, the client must have created an Application Key on the 
  # "Account Settings" page here: https://app.datadoghq.com/account/settings
  # It should be passed along from the node/role/environemnt attributes, as the default is nil.
  def initialize(opts = {})
    @api_key = opts[:api_key]
    @application_key = opts[:application_key]
    @dog = Dogapi::Client.new(@api_key, application_key = @application_key)
  end

  def report
    # Send the metrics
    begin
      @dog.emit_point("chef.resources.total", run_status.all_resources.length, :host => run_status.node.name)
      @dog.emit_point("chef.resources.updated", run_status.updated_resources.length, :host => run_status.node.name)
      @dog.emit_point("chef.resources.elapsed_time", run_status.elapsed_time, :host => run_status.node.name)
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
      Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
    end
  
    event_title = ""
    run_time = pluralize(run_status.elapsed_time, "second")
    if run_status.success?
      alert_type = "success"
      event_priority = "low"
      event_title << "Chef completed in #{run_time} on #{run_status.node.name} "
    else
      event_title << "Chef failed in #{run_time} on #{run_status.node.name} "
    end

    event_data = "Chef updated #{run_status.updated_resources.length} resources out of #{run_status.all_resources.length} resources total."
    if run_status.updated_resources.length.to_i > 0
      event_data << "\n@@@\n"
      run_status.updated_resources.each do |r|
        event_data << "- #{r.to_s} (#{r.defined_at})\n"
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
      @dog.emit_event(Dogapi::Event.new(event_data, 
                                        :msg_title => event_title, 
                                        :event_type => 'config_management.run',
                                        :event_object => run_status.node.name,
                                        :alert_type => alert_type,
                                        :priority => event_priority
                                        ), :host => run_status.node.name)

      # Get the current list of tags, remove any "role:" entries
      host_tags = @dog.host_tags(node.name)[1]["tags"]
      host_tags.delete_if {|tag| tag.start_with?('role:') } unless host_tags.nil?

      # Get list of chef roles, rename them to tag format
      chef_roles = node.run_list.roles
      chef_roles.collect! {|role| "role:" + role }

      # Combine (union) both arrays. Removes dupes, preserves non-chef tags.
      new_host_tags = host_tags | chef_roles

      # Replace all tags with the new tags
      @dog.update_tags(node.name, new_host_tags)

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
end
