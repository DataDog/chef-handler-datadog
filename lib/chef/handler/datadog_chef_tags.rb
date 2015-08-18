# encoding: utf-8
require 'rubygems'
require 'chef/handler'
require 'chef/mash'
require 'dogapi'

# helper class for sending datadog tags from chef runs
class DatadogChefTags
  def initialize
    @node = nil
    @run_status = nil
    @application_key = nil
    @combined_host_tags = nil
  end

  # set the dogapi client handle
  #
  # @param dogapi_client [Dogapi::Client] datadog api client handle
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
  end

  # attribute accessor for combined array of tags
  #
  # @return [Array] the set of host tags based off the chef run
  attr_reader :combined_host_tags

  # set the chef run status used for the report
  #
  # @param run_status [Chef::RunStatus] current chef run status
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_run_status(run_status)
    @run_status = run_status
    # Build up an array of Chef tags that will be sent back
    # Selects all [env, roles, tags] from the Node's object and reformats
    # them to `key:value` e.g. `role:database-master`.
    @node = run_status.node
    # generate the combined tags
    chef_env = node_env.split # converts a string into an array
    chef_roles = node_roles
    chef_tags = node_tags

    # Combine (union) all arrays. Removes duplicates if found.
    @combined_host_tags = chef_env | chef_roles | chef_tags
    self
  end

  # set the target hostname (chef node name)
  #
  # @param hostname [String] hostname to use for the handler report
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_hostname(hostname)
    @hostname = hostname
    self
  end

  # set the datadog application key
  #
  # TODO: the application key is only needed for error checking, e.g. an app key exists
  #   would be cleaner to push this check up to the data prep method in the
  #   calling handler class
  #
  # @param application_key [String] datadog application key used for chef reports
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_application_key(application_key)
    @application_key = application_key
    if @application_key.nil?
      Chef::Log.warn('You need an application key to let Chef tag your nodes ' \
              'in Datadog. Visit https://app.datadoghq.com/account/settings#api to ' \
                'create one and update your datadog attributes in the datadog cookbook.'
      )
      fail ArgumentError, 'Missing Datadog Application Key'
    end
    self
  end

  # send updated chef run generated tags to Datadog
  def send_update_to_datadog
    rc = @dog.update_tags(@hostname, combined_host_tags, 'chef')
    begin
      # See FIXME above about why I feel dirty repeating this code here
      if rc.length < 2
        Chef::Log.warn("Unexpected response from Datadog Event API: #{rc}")
      else
        if rc[0].to_i / 100 != 2
          Chef::Log.warn("Could not submit #{combined_host_tags} tags for #{@hostname} to Datadog: #{rc}")
        else
          Chef::Log.debug("Successfully updated #{@hostname}'s tags to #{combined_host_tags.join(', ')}")
        end
      end
    rescue
      Chef::Log.warn("Could not determine whether #{@hostname}'s tags were successfully submitted to Datadog: #{rc}")
    end
  end

  private

  def node_roles
    @node.run_list.roles.map! { |role| 'role:' + role }
  end

  def node_env
    'env:' + @node.chef_environment if @node.respond_to?('chef_environment')
  end

  def node_tags
    @node.tags.map! { |tag| 'tag:' + tag }
  end
end # end class DatadogChefTags
