# encoding: utf-8
require 'dogapi'

# helper class for sending datadog metrics from a chef run
class DatadogChefMetrics
  def initialize
    @dog = nil
    @hostname = ''
    @run_status = nil
  end

  def and
    self
  end

  # @param dogapi_client [Dogapi::Client] datadog api client
  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
  end

  # @param hostname [String] hostname used for reporting metrics
  def for_hostname(hostname)
    @hostname = hostname
    self
  end

  # @param run_status [Chef::RunStatus] current run status
  def using_run_status(run_status)
    @run_status = run_status
    self
  end

  # Emit Chef metrics to Datadog
  def emit_to_datadog
    # If there is a failure during compile phase, a large portion of
    # run_status may be unavailable. Bail out here
    warn_msg = 'Error during compile phase, no Datadog metrics available.'
    return Chef::Log.warn(warn_msg) if @run_status.elapsed_time.nil?

    @dog.emit_point('chef.resources.total', @run_status.all_resources.length, host: @hostname)
    @dog.emit_point('chef.resources.updated', @run_status.updated_resources.length, host: @hostname)
    @dog.emit_point('chef.resources.elapsed_time', @run_status.elapsed_time, host: @hostname)
    Chef::Log.debug('Submitted Chef metrics back to Datadog')
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
  end
end # end class DatadogChefMetrics
