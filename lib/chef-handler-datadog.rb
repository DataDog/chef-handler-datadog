require 'rubygems'
require 'chef'
require 'chef/handler'
require 'dogapi'

class DataDog < Chef::Handler
  def initialize(api_key)
    @api_key = api_key
    @dog = Dogapi::Client.new(api_key)
  end

  def report
    # Send the metrics
    begin
      @dog.emit_point("chef.resources.total", run_status.all_resources.length, :host => run_status.node.name)
      @dog.emit_point("chef.resources.updated", run_status.updated_resources.length, :host => run_status.node.name)
      @dog.emit_point("chef.resources.elapsed_time", run_status.elapsed_time, :host => run_status.node.name)
    rescue Errno::ECONNREFUSED => e
      Chef::Log.error("Could not send metrics to DataDog. Connection error:\n" + e)
    end
  
    event_title = ""
    if run_status.success?
      event_title << "Chef completed in #{run_status.elapsed_time} seconds on #{run_status.node.name} "
    else
      event_title << "Chef failed in #{run_status.elapsed_time} seconds on #{run_status.node.name} "
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
      event_data << "\n@@@\n#{run_status.formatted_exception}\n@@@\n"
      event_data << "\n@@@\n#{run_status.backtrace.join("\n")}\n@@@\n"
    end

    # Submit the details back to DataDog
    begin
      @dog.emit_event(Dogapi::Event.new(event_data, :msg_title => event_title), :host => run_status.node.name)
      # TODO: add chef roles to set the node's #tags in newsfeed
    rescue Errno::ECONNREFUSED => e
      Chef::Log.error("Could not connect to Datadog. Connection error:\n" + e)
      Chef::Log.error("Data to be submitted was:")
      Chef::Log.error(event_title)
      Chef::Log.error(event_data)
    end
  end
end
