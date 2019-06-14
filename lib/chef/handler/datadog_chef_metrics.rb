# encoding: utf-8
require 'dogapi'

require_relative 'datadog_util'

# helper class for sending datadog metrics from a chef run
class DatadogChefMetrics
  include DatadogUtil

  def initialize
    @hostname = ''
    @run_status = nil
  end

  # set the target hostname (chef node name)
  #
  # @param hostname [String] hostname used for reporting metrics
  # @return [DatadogChefMetrics] instance reference to self enabling method chaining
  def with_hostname(hostname)
    @hostname = hostname
    self
  end

  # set the chef run status used for the report
  #
  # @param run_status [Chef::RunStatus] current run status
  # @return [DatadogChefMetrics] instance reference to self enabling method chaining
  def with_run_status(run_status)
    @run_status = run_status
    self
  end

  # Emit Chef metrics to Datadog
  #
  # @param dog [Dogapi::Client] Dogapi Client to be used
  def emit_to_datadog(dog)
    # Send base success/failure metric
    dog.emit_point('chef.run.success', @run_status.success? ? 1 : 0, host: @hostname, type: 'counter')
    dog.emit_point('chef.run.failure', @run_status.success? ? 0 : 1, host: @hostname, type: 'counter')

    # If there is a failure during compile phase, a large portion of
    # run_status may be unavailable. Bail out here
    warn_msg = 'Error during compile phase, no Datadog metrics available.'
    return Chef::Log.warn(warn_msg) if compile_error?

    dog.emit_point('chef.resources.total', @run_status.all_resources.length, host: @hostname)
    dog.emit_point('chef.resources.updated', @run_status.updated_resources.length, host: @hostname)
    dog.emit_point('chef.resources.elapsed_time', @run_status.elapsed_time, host: @hostname)
    Chef::Log.debug('Submitted Chef metrics back to Datadog')
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    Chef::Log.warn("Could not send metrics to Datadog. Connection error:\n" + e)
  rescue StandardError => e
    Chef::Log.warn("Could not determine whether chef run metrics were successfully submitted to Datadog. Error:\n#{e}")
  end
end # end class DatadogChefMetrics
