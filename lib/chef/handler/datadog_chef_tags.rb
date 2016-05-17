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
    @tag_prefix = 'tag:'
    @scope_prefix = nil
    @retries = 0
    @combined_host_tags = nil
    @regex_black_list = nil
  end

  # set the dogapi client handle
  #
  # @param dogapi_client [Dogapi::Client] datadog api client handle
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_dogapi_client(dogapi_client)
    @dog = dogapi_client
    self
  end

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

  # set the prefix to be added to all Chef tags
  #
  # @param tag_prefix [String] prefix to be added to all Chef tags
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_tag_prefix(tag_prefix)
    @tag_prefix = tag_prefix unless tag_prefix.nil?
    self
  end

  # set the number of retries when sending tags, when the host is not yet present
  # on Datadog
  #
  # @param retries [Integer] number of retries
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_retries(retries)
    @retries = retries unless retries.nil?
    self
  end

  def with_tag_blacklist(tags_blacklist_regex)
    @regex_black_list = Regexp.new(tags_blacklist_regex, Regexp::IGNORECASE) unless tags_blacklist_regex.nil? || tags_blacklist_regex.empty?
    self
  end

  # set the prefix to be added to Datadog tags (Role, Env)
  #
  # @param scope_prefix [String] prefix to be added to Datadog tags
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_scope_prefix(scope_prefix)
    @scope_prefix = scope_prefix unless scope_prefix.nil?
    self
  end

  # send updated chef run generated tags to Datadog
  def send_update_to_datadog
    tags = combined_host_tags
    retries = @retries
    begin
      loop do
        should_retry = false
        rc = @dog.update_tags(@hostname, tags, 'chef')
        # See FIXME in DatadogChefEvents::emit_to_datadog about why I feel dirty repeating this code here
        if rc.length < 2
          Chef::Log.warn("Unexpected response from Datadog Tags API: #{rc}")
        else
          if retries > 0 && rc[0].to_i == 404
            Chef::Log.debug("Host #{@hostname} not yet present on Datadog, re-submitting tags in 2 seconds")
            sleep 2
            retries -= 1
            should_retry = true
          elsif rc[0].to_i / 100 != 2
            Chef::Log.warn("Could not submit #{tags} tags for #{@hostname} to Datadog: #{rc}")
          else
            Chef::Log.debug("Successfully updated #{@hostname}'s tags to #{tags.join(', ')}")
          end
        end
        break unless should_retry
      end
    rescue
      Chef::Log.warn("Could not determine whether #{@hostname}'s tags were successfully submitted to Datadog: #{rc}")
    end
  end

  # return a combined array of tags that should be sent to Datadog
  #
  # @return [Array] the set of host tags based off the chef run
  def combined_host_tags
    # Combine (union) all arrays. Removes duplicates if found.
    node_env.split | node_roles | node_tags
  end

  private

  def node_roles
    @node.run_list.roles.map! { |role| "#{@scope_prefix}role:#{role}" }
  end

  def node_env
    "#{@scope_prefix}env:#{@node.chef_environment}" if @node.respond_to?('chef_environment')
  end

  def node_tags
    return [] unless @node.tags
    output = @node.tags.map { |tag| "#{@tag_prefix}#{tag}" }

    # No blacklist, return all results
    return output if @regex_black_list.nil?

    # The blacklist is set, so return the items which are not filtered by it.
    output.select { |t| !@regex_black_list.match(t) }
  end
end # end class DatadogChefTags
