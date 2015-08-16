# encoding: utf-8
require 'rubygems'
require 'chef/handler'
require 'chef/mash'
require 'dogapi'

class DatadogChefEvents
  def initialize
    @dog = nil
    @hostname = nil
    @run_status = nil
    @failure_notfications = nil

    @alert_type = ''
    @event_priority = ''
    @event_title = ''
    @event_body = ''
  end

  def and
    self
  end

  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
  end

  def for_hostname(hostname)
    @hostname = hostname
    self
  end

  def using_run_status(run_status)
    @run_status = run_status
    self
  end

  def with_failure_notifications(failure_notifications)
    @failure_notifications = failure_notifications
    self
  end

  def with_tags(tags)
    @tags = tags
    self
  end

  def emit_to_datadog
    @event_body = ''
    build_event_data
    evt = @dog.emit_event(Dogapi::Event.new(@event_body,
                                            msg_title: @event_title,
                                            event_type: 'config_management.run',
                                            event_object: @hostname,
                                            alert_type: @alert_type,
                                            priority: @event_priority,
                                            source_type_name: 'chef',
                                            tags: @tags
    ), host: @hostname)

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
          Chef::Log.debug("Successfully submitted Chef event to Datadog for #{@hostname} at #{evt[1]['event']['url']}")
        end
      end
    rescue
      Chef::Log.warn("Could not determine whether chef run was successfully submitted to Datadog: #{evt}")
    end
  end

  private

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

  def update_resource_list
    # Compose a list of resources updated during a run.
    # Shorten the list when there is a failure for stacktrace debugging
    # No resources updated? set an empty event_body

    if @run_status.updated_resources.length.to_i > 0
      if @run_status.failed?
        report_resources = @run_status.updated_resources.last(5)
      else
        report_resources = @run_status.updated_resources
      end

      @event_body = "\n$$$\n"
      report_resources.each do |r|
        @event_body << "- #{r} (#{r.defined_at})\n"
      end
      @event_body << "\n$$$\n"
    end
  end

  # Build the Event data for submission
  #
  # @param hostname [String] resolved hostname to attach to Event
  # @param run_status [Chef::RunStatus] current run status
  # @param notify_on_failure [Array] array of notification handles
  # @return [Array] alert_type, event_priority, event_title, event_body
  def build_event_data
    # bail early in case of a compiletime failure
    # OPTIMIZE: Use better inspectors to handle failure scenarios, refactor needed.
    if @run_status.elapsed_time.nil?
      @alert_type = 'error'
      @event_title = "Chef failed during compile phase on #{@hostname} "
      @event_priority = 'normal'
      @event_body = 'Chef was unable to complete a run, an error during compilation may have occurred.'
    else
      run_time = pluralize(@run_status.elapsed_time, 'second')

      # This is the first line of the Event body, the rest is appended here.
      @event_body = "Chef updated #{@run_status.updated_resources.length} resources out of #{@run_status.all_resources.length} resources total."

      # Show the updated resource list, truncated when failed to 5
      # @event_body << updated_resource_list
      update_resource_list

      if @run_status.success?
        @alert_type = 'success'
        @event_priority = 'low'
        @event_title = "Chef completed in #{run_time} on #{@hostname} "
      else
        @alert_type = 'error'
        @event_priority = 'normal'
        @event_title = "Chef failed in #{run_time} on #{@hostname} "

        if @failure_notifications
          handles = @failure_notifications
          # convert the notification handle array to a string
          @event_body << "\nAlerting: #{handles.join(' ')}\n"
        end

        @event_body << "\n$$$\n#{@run_status.formatted_exception}\n$$$\n"
        @event_body << "\n$$$\n#{@run_status.backtrace.join("\n")}\n$$$\n"
      end
    end
  end
end # end module DatadogChefEvent
