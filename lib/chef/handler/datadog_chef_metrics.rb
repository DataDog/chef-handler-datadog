# encoding: utf-8
require 'dogapi'

DEFAULT_RESOURCE_CLASS = 'role'
DEPLOY_STAGE_NAME = 'deploy'
BUILD_STAGE_NAME = 'build'

# helper class for sending datadog metrics from a chef run
class DatadogChefMetrics
  attr_accessor :details
  attr_reader :log_file_path

  def initialize
    @dog = nil
    @hostname = ''
    @run_status = nil
    @details = nil
    @log_results = false
    @log_file_path = "/tmp/chef-metrics-#{Time.now.to_i}.json"
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
    @node = run_status.node
    self
  end

  # enables storing the metrics' dump locally
  #
  # @param enabled [Bool] option to enable caching of results in /tmp
  # @return [DatadogChefMetrics] instance reference to self enabling method chaining
  def with_log(enabled)
    @log_results = enabled
    self
  end

  # sets a list of cookbooks considered base platform
  #
  # @param Array::String
  # @return [DatadogChefMetrics] instance reference to self enabling method chaining
  def with_resource_class_map(resource_class_map)
    @resource_class_map ||= resource_class_map || {}
    self
  end

  # Emit Chef metrics to Datadog
  def emit_to_datadog
    # If there is a failure during compile phase, a large portion of
    # run_status may be unavailable. Bail out here
    warn_msg = 'Error during compile phase, no Datadog metrics available.'
    return Chef::Log.warn(warn_msg) if @run_status.elapsed_time.nil?

    # HACK: we're loosing role information, only 1 gets populated
    env_tags = {
      realm: @node[:realm],
      stage: @node[:realm] ? DEPLOY_STAGE_NAME : BUILD_STAGE_NAME,
      environment_realm: @node[:environment_realm],
      instance_type: @node[:instance_type],
      ami_id: @node[:ami_id],
      host_sid: @node[:host_sid],
      role: @node.run_list.roles[0]
    }

    collect_detailed_resource_metrics(env_tags)
    write_detailed_resource_metrics if @log_results

    @dog.batch_metrics do
      @details.each { |m| @dog.emit_point(m[:name], m[:value], host: @hostname, tags: m[:tags]) }
      @dog.emit_point('chef.resources.total', @run_status.all_resources.length, host: @hostname)
      @dog.emit_point('chef.resources.updated', @run_status.updated_resources.length, host: @hostname)
      @dog.emit_point('chef.resources.elapsed_time', @run_status.elapsed_time, host: @hostname)
    end
    Chef::Log.debug('Submitted Chef metrics back to Datadog')
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    Chef::Log.error("Could not send metrics to Datadog. Connection error:\n" + e)
  end

  # collect all resource metrics from the @run_status
  def collect_detailed_resource_metrics(extra_tags = {})
    @details ||= @run_status.all_resources.each_with_object([]) do |resource, resource_metrics|
      resource_metric_tags = {
        resource_name:     resource.name,
        cookbook:          resource.cookbook_name,
        recipe:            resource.recipe_name,
        updated:           resource.updated,
        resource_class:    resource_class(resource.cookbook_name)
      }.merge!(extra_tags)

      resource_metrics << { name: 'chef.resources.convergence_time',
                            tags: resource_metric_tags.map { |k, v| "#{k}:#{v}" },
                            value: resource.elapsed_time }
    end
  end

  private

  # assign extra properties to the resource based on the configuration dict
  # this is used to define owners of the particular resource for tracing
  def resource_class(cookbook_name)
    @resource_class_map[cookbook_name] || DEFAULT_RESOURCE_CLASS
  end

  # dump raw metrics to a file in the directory
  def write_detailed_resource_metrics
    warn_msg = 'No metrics to be written. Not creating file'
    return Chef::Log.warn(warn_msg) unless @details

    File.open(@log_file_path, 'w+') { |f| f.write(JSON.dump(@details)) }
    Chef::Log.info("Saved metrics to file: #{@log_file_path}")
  rescue StandardError
    Chef::Log.error("Could not save the status to the file in: #{@log_file_path}")
  end
end # end class DatadogChefMetrics
