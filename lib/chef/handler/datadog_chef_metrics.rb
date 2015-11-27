# encoding: utf-8
require 'dogapi'

# helper class for sending datadog metrics from a chef run
class DatadogChefMetrics
  attr_reader :details

  def initialize
    @dog = nil
    @hostname = ''
    @run_status = nil
    @details = []
  end

  # set the dogapi client handle
  #
  # @param dogapi_client [Dogapi::Client] datadog api client
  # @return [DatadogChefMetrics] instance reference to self enabling method chaining
  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
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
  def emit_to_datadog
    # If there is a failure during compile phase, a large portion of
    # run_status may be unavailable. Bail out here
    warn_msg = 'Error during compile phase, no Datadog metrics available.'
    return Chef::Log.warn(warn_msg) if @run_status.elapsed_time.nil?

    @dog.batch_metrics do
      collect_detailed_resource_metrics
      @details.each do |m|
        @dog.emit_point(m[:name], m[:value], host: @hostname, tags: m[:tags])
      end
      @dog.emit_point('chef.resources.total', @run_status.all_resources.length, host: @hostname)
      @dog.emit_point('chef.resources.updated', @run_status.updated_resources.length, host: @hostname)
      @dog.emit_point('chef.resources.elapsed_time', @run_status.elapsed_time, host: @hostname)
    end
    Chef::Log.debug('Submitted Chef metrics back to Datadog')
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
  end

  private

  # collect all resource metrics from the @run_status
  def collect_detailed_resource_metrics
    @details = @run_status.all_resources.each_with_object([]) do |resource, resource_metrics|
      resource_metric_tags = {
        resource_name:     resource.name,
        cookbook:          resource.cookbook_name,
        recipe:            resource.recipe_name
      }

      resource_metrics << { name: 'chef.resources.convergence_time',
                            tags: resource_metric_tags.map { |k, v| "#{k}:#{v}" }.join(' '),
                            value: resource.elapsed_time }
    end
  end
end # end class DatadogChefMetrics
