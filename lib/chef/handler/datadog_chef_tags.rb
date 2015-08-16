# encoding: utf-8
require 'rubygems'
require 'chef/handler'
require 'chef/mash'
require 'dogapi'

# helper class for sending datadog tags from chef runs
class DatadogChefTags
  def initialize(node = nil)
    @node = node
    @application_key = nil
    @combined_host_tags = nil
  end

  def and
    self
  end

  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
  end

  # @param node [Chef::Node]
  # @return [DatadogChefTags]
  def for_node(node)
    @node = node
    # generate the combined tags
    chef_env = node_env.split # converts a string into an array
    chef_roles = node_roles
    chef_tags = node_tags

    # Combine (union) all arrays. Removes duplicates if found.
    @combined_host_tags = chef_env | chef_roles | chef_tags
    self
  end

  def for_hostname(hostname)
    @hostname = hostname
    self
  end

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

  # Build up an array of Chef tags to send back
  #
  # Selects all [env, roles, tags] from the Node's object and reformats
  # them to `key:value` e.g. `role:database-master`.
  # @return [Array] current Chef env, roles, tags
  attr_reader :combined_host_tags
  # def combined_host_tags
  #   @combined_host_tags
  # end

  # Replace all Chef tags with the found Chef tags
  def update_to_datadog
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
end
