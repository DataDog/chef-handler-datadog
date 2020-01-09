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
    @policy_tags_enabled = false
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

  # set the blacklist regexp, node tags matching this regex won't be sent
  #
  # @param tags_blacklist_regex [String] regexp-formatted string
  # @return [DatadogChefTags] instance reference to self enabling method chaining
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

  # enable policy tags
  #
  # @param enabled [TrueClass,FalseClass] enable or disable policy tags
  # @return [DatadogChefTags] instance reference to self enabling method chaining
  def with_policy_tags_enabled(enabled)
    @policy_tags_enabled = enabled unless enabled.nil?
    self
  end

  # send updated chef run generated tags to Datadog
  #
  # @param dog [Dogapi::Client] Dogapi Client to be used
  def send_update_to_datadog(dog)
    tags = combined_host_tags
    retries = @retries
    rc = []
    begin
      loop do
        should_retry = false
        rc = dog.update_tags(@hostname, tags, 'chef')
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
    rescue StandardError => e
      Chef::Log.warn("Could not determine whether #{@hostname}'s tags were successfully submitted to Datadog: #{rc.inspect}. Error:\n#{e}")
    end
  end

  # return a combined array of tags that should be sent to Datadog
  #
  # @return [Array] the set of host tags based off the chef run
  def combined_host_tags
    # Combine (union) all arrays. Removes duplicates if found.
    node_env.split | node_roles | node_policy_tags | node_tags
  end

  private

  def node_roles
    @node.run_list.roles.map! { |role| "#{@scope_prefix}role:#{role}" }
  end

  def node_env
    "#{@scope_prefix}env:#{@node.chef_environment}" if @node.respond_to?('chef_environment')
  end

  # Send the policy name and policy group as chef tags when using chef policyfiles feature
  # The policy_group and policy_name attributes exist only for chef >= 12.5.1
  def node_policy_tags
    policy_tags = []
    if @policy_tags_enabled
      if @node.respond_to?('policy_group') && !@node.policy_group.nil?
        policy_tags << "#{@scope_prefix}policy_group:#{@node.policy_group}"
      end
      if @node.respond_to?('policy_name') && !@node.policy_name.nil?
        policy_tags << "#{@scope_prefix}policy_name:#{@node.policy_name}"
      end
    end
    policy_tags
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
