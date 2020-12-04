# encoding: utf-8
require 'spec_helper'

describe Chef::Handler::Datadog, vcr: :new_episodes do
  # The #report method currently long and clunky, and we need to simulate a
  # Chef run to test all aspects of this, as well as push values into the test.
  before(:all) do
    # This is used in validating that requests have actually been made,
    # as in a 'Fucntional test'. We've recorded the tests with VCR, and use
    # these to assert that the final product is correct. This is also
    # exercising the API client, which may be helpful as well.
    # There is a fair amount of duplication in the repsonse returned.
    BASE_URL          = 'https://app.datadoghq.com'
    EVENTS_ENDPOINT   = BASE_URL + '/api/v1/events'
    HOST_TAG_ENDPOINT = BASE_URL + '/api/v1/tags/hosts/'
    METRICS_ENDPOINT  = BASE_URL + '/api/v1/series'
  end

  before(:each) do
    @handler = Chef::Handler::Datadog.new(
      api_key: API_KEY,
      application_key: APPLICATION_KEY,
    )
  end

  describe 'initialize' do
    it 'should allow config hash to have string keys' do
      Chef::Handler::Datadog.new(
        api_key: API_KEY,
        application_key: APPLICATION_KEY,
        tag_prefix: 'tag',
        scope_prefix: nil
      )
    end

    it 'should create a Dogapi client for the endpoint' do
      dogs = @handler.instance_variable_get(:@dogs)

      # Check that we do have a Dogapi client
      expect(dogs.length).to eq(1)
    end
  end



  describe 'reports metrics event and sets tags' do
    # Construct a good run_status
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test')
      @node.send(:chef_environment, 'testing')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context

      # Run the report
      @handler.run_report_unsafe(@run_status)
    end

    context 'emits metrics' do
      it 'reports metrics' do
        expect(a_request(:post, METRICS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] }
        )).to have_been_made.times(5)
      end
    end

    context 'emits events' do
      it 'posts an event' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] },
          body: hash_including(msg_text: 'Chef updated 0 resources out of 0 resources total.',
                               msg_title: "Chef completed in 5 seconds on #{@node.name} ",
                               tags: ['env:testing']),
        )).to have_been_made.times(1)
      end

      it 'sets priority correctly' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] },
          body: hash_including(alert_type: 'success',
                               priority: 'low'),
        )).to have_been_made.times(1)
      end
    end

    context 'sets tags' do
      it 'puts the tags for the current node' do
        # We no longer need to query the tag api for current tags,
        # rather udpate only the tags for the designated source type
        expect(a_request(:get, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
        )).to have_been_made.times(0)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: { tags: ['env:testing'] },
        )).to have_been_made.times(1)
      end
    end
  end

  describe 'reports correct hostname on an ec2 node' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-ec2')
      @node.send(:chef_environment, 'testing')

      @node.automatic_attrs['ec2'] = { instance_id: 'i-123456' }

      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)
      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock
      @run_status.run_context = @run_context
    end

    it 'uses the instance id when no config specified' do
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: 'Chef completed in 5 seconds on i-123456 ',
                             host: 'i-123456'),
      )).to have_been_made.times(1)
    end

    it 'uses the instance id when config is specified' do
      @handler.config[:use_ec2_instance_id] = true
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: 'Chef completed in 5 seconds on i-123456 ',
                             host: 'i-123456'),
      )).to have_been_made.times(1)
    end

    it 'does not use the instance id when config specified to false' do
      @handler.config[:use_ec2_instance_id] = false
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: "Chef completed in 5 seconds on #{@node.name} ",
                             host: @node.name),
      )).to have_been_made.times(1)
    end
  end

  context 'hostname' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-hostname')
      @node.send(:chef_environment, 'testing')

      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)
      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock
      @run_status.run_context = @run_context
    end

    it 'uses the node.name when no config specified' do
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: "Chef completed in 5 seconds on #{@node.name} ",
                             host: @node.name),
      )).to have_been_made.times(1)
    end

    it 'uses the specified hostname when provided' do
      @handler.config[:hostname] = 'my-imaginary-hostname.local'
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: 'Chef completed in 5 seconds on my-imaginary-hostname.local ',
                             host: 'my-imaginary-hostname.local'),
      )).to have_been_made.times(1)
    end

    describe 'when dogapi-rb fails to calculate a hostname' do
      before(:each) do 
          allow(Dogapi::Client).to receive(:new).and_raise("getaddrinfo: Name or service not known")

          @handler = Chef::Handler::Datadog.new(
            api_key: API_KEY,
            application_key: APPLICATION_KEY,
          )
      end

      it 'the reporter should not fail the chef run' do
        @handler.config[:hostname] = 'my-imaginary-hostname.local'
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:post, EVENTS_ENDPOINT)).to have_been_made.times(0)
      end
    end
  end

  context 'tags' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-tags')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')

      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context
    end

    describe 'when specified' do
      it 'sets the role and env and tags' do
        @node.normal['tags'] = ['the_one_and_only', 'datacenter:my-cloud']
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'env:hostile', 'role:highlander', 'tag:the_one_and_only', 'tag:datacenter:my-cloud'
            ]),
        )).to have_been_made.times(1)
      end

      it 'allows for user-specified tag prefix' do
        @node.normal['tags'] = ['the_one_and_only', 'datacenter:my-cloud']
        @handler.config[:tag_prefix] = 'custom-prefix-'
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'env:hostile', 'role:highlander', 'custom-prefix-the_one_and_only', 'custom-prefix-datacenter:my-cloud'
            ]),
         )).to have_been_made.times(1)
      end

      it 'allows for empty tag prefix' do
        @node.normal['tags'] = ['the_one_and_only', 'datacenter:my-cloud']
        @handler.config[:tag_prefix] = ''
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'env:hostile', 'role:highlander', 'the_one_and_only', 'datacenter:my-cloud'
            ]),
         )).to have_been_made.times(1)
      end

      it 'allows for user-specified scope prefix' do
        @handler.config[:scope_prefix] = 'custom-prefix-'
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'custom-prefix-env:hostile', 'custom-prefix-role:highlander'
            ]),
         )).to have_been_made.times(1)
      end

      it 'allows for empty scope prefix' do
        @handler.config[:scope_prefix] = ''
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'env:hostile', 'role:highlander'
            ]),
         )).to have_been_made.times(1)
      end
    end

    describe 'when unspecified' do
      it 'sets role, env and nothing else' do
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
            'env:hostile', 'role:highlander'
            ]),
        )).to have_been_made.times(1)
      end
    end

    describe 'when tag blacklist is specified' do
      it 'does not include the tag(s) specified' do
        @node.normal['tags'] = ['allowed_tag', 'not_allowed_tag']
        @handler.config[:tags_blacklist_regex] = 'not_allowed.*'
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
              'env:hostile', 'role:highlander', 'tag:allowed_tag'
            ]),
        )).to have_been_made.times(1)
      end
    end

    describe 'when tag blacklist is unspecified' do
      it 'should include all of the tag(s)' do
        @node.normal['tags'] = ['allowed_tag', 'not_allowed_tag']
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
              'env:hostile', 'role:highlander', 'tag:allowed_tag', 'tag:not_allowed_tag'
            ]),
        )).to have_been_made.times(1)
      end
    end

    describe 'when policy tags are not enabled' do
      # This feature is available only for chef >= 12.5.1
      if Chef::Version.new(Chef::VERSION) < Chef::Version.new("12.5.1")
        next
      end
      it 'does not set the policy name and policy group tags' do
        @node.send(:policy_name, 'the_policy_name')
        @node.send(:policy_group, 'the_policy_group')
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
              'env:hostile', 'role:highlander'
            ]),
        )).to have_been_made.times(1)
      end
    end

    describe 'when policy tags are enabled' do
      # This feature is available only for chef >= 12.5.1
      if Chef::Version.new(Chef::VERSION) < Chef::Version.new("12.5.1")
        next
      end
      it 'sets the policy name and policy group tags' do
        @node.send(:policy_name, 'the_policy_name')
        @node.send(:policy_group, 'the_policy_group')
        @handler.config[:send_policy_tags] = true
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          headers: { 'Dd-Api-Key' => @handler.config[:api_key],
                     'Dd-Application-Key' => @handler.config[:application_key] },
          query: { source: 'chef' },
          body: hash_including(tags: [
              'env:hostile', 'role:highlander', 'policy_group:the_policy_group', 'policy_name:the_policy_name'
            ]),
        )).to have_been_made.times(1)
      end
    end
  end

  context 'tags submission retries' do
    let(:dog) do
      @handler.instance_variable_get(:@dogs)[0]
    end

    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-tags-retries')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')
      @node.normal['tags'] = ['the_one_and_only']

      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)
      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context
    end

    describe 'when specified as 2 retries' do
      before(:each) do
        @handler.config[:tags_submission_retries] = 2
        # Stub `sleep` to avoid slowing down the execution
        allow_any_instance_of(DatadogChefTags).to receive(:sleep)
      end

      it 'retries no more than twice' do
        # Define mock update_tags function which returns the result of an HTTP 404 error
        allow(dog).to receive(:update_tags).and_return([404, 'Not Found'])

        expect(dog).to receive(:update_tags).exactly(3).times
        @handler.run_report_unsafe(@run_status)
      end

      it 'stops retrying once submission is successful' do
        # Define mock update_tags function which returns the result of an HTTP 404 error once
        allow(dog).to receive(:update_tags).and_return([404, 'Not Found'], [201, 'Created'])

        expect(dog).to receive(:update_tags).exactly(2).times
        @handler.run_report_unsafe(@run_status)
      end
    end

    describe 'when not specified' do
      it 'does not retry after a failed submission' do
        # Define mock update_tags function which returns the result of an HTTP 404 error
        allow(dog).to receive(:update_tags).and_return([404, 'Not Found'])


        expect(dog).to receive(:update_tags).exactly(:once)
        @handler.run_report_unsafe(@run_status)
      end
    end
  end

  describe 'handles no application_key' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-noapp')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')
      @node.normal['tags'] = ['the_one_and_only']

      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context
    end

    it 'fails when no application key is provided' do
      # TODO: figure out how to capture output of Chef::Log
      # Run the report, catch the error
      expect { Chef::Handler::Datadog.new(api_key: API_KEY, application_key: nil) }.to raise_error
    end
  end

  describe 'failed Chef run' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-failed')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')
      @node.normal['tags'] = ['the_one_and_only']

      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      all_resources = [
        Chef::Resource.new('whiskers'),
        Chef::Resource.new('paws'),
        Chef::Resource.new('ears'),
        Chef::Resource.new('nose'),
        Chef::Resource.new('tail'),
        Chef::Resource.new('fur')
      ]
      all_resources.map { |r| r.updated_by_last_action(true) }
      @run_context.resource_collection.all_resources.replace(all_resources)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 2)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context

      # Construct an exception
      exception = Chef::Exceptions::UnsupportedAction.new('Something awry.')
      exception.set_backtrace(['whiskers.rb:2', 'paws.rb:1', 'file.rb:2', 'file.rb:1'])
      @run_status.exception = exception

      # Run the report
      @handler.run_report_unsafe(@run_status)
    end

    it 'sets event title correctly' do
      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(msg_title: "Chef failed in 2 seconds on #{@node.name} "),
      )).to have_been_made.times(1)
    end

    it 'sets priority correctly' do
      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: hash_including(alert_type: 'error',
                             priority: 'normal'),
      )).to have_been_made.times(1)
    end

    it 'sets alert handles when specified' do
      @handler.config[:notify_on_failure] = ['@alice', '@bob']
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        body: /Alerting: @alice @bob/
      )).to have_been_made.times(1)
    end
  end

  describe 'updated resources' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-resources')
      @node.send(:chef_environment, 'resources')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      all_resources = [Chef::Resource.new('whiskers'), Chef::Resource.new('paws')]
      all_resources.first.updated_by_last_action(true)
      @run_context.resource_collection.all_resources.replace(all_resources)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 8)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context

      # Run the report
      @handler.run_report_unsafe(@run_status)
    end

    it 'posts an event' do
      expect(a_request(:post, EVENTS_ENDPOINT).with(
        query: { api_key: @handler.config[:api_key] },
        # FIXME: msg_text is "\n$$$\n- [whiskers] (dynamically defined)\n\n$$$\n" - is this a bug?
        body: hash_including(#msg_text: 'Chef updated 1 resources out of 2 resources total.',
                             msg_title: "Chef completed in 8 seconds on #{@node.name} "),
      )).to have_been_made.times(1)
    end
  end

  describe 'resources' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-resources')
      @node.send(:chef_environment, 'resources')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_status = Chef::RunStatus.new(@node, @events)
    end

    context 'failure during compile phase' do
      before(:each) do
        @handler.run_report_unsafe(@run_status)
      end

      it 'only emits the run status metrics' do
        expect(a_request(:post, METRICS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] }
        )).to have_been_made.times(2)
      end

      it 'posts an event' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] },
          body: hash_including(msg_text: 'Chef was unable to complete a run, an error during compilation may have occurred.',
                               msg_title: "Chef failed during compile phase on #{@node.name} "),
        )).to have_been_made.times(1)
      end
    end

    context 'failure during compile phase with an elapsed time and incomplete resource collection' do
      before(:each) do
        @run_context = Chef::RunContext.new(@node, {}, @events)

        allow(@run_context.resource_collection).to receive(:all_resources).and_return(nil)
        @run_status.run_context = @run_context

        @expected_time = Time.now
        allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
        @run_status.start_clock
        @run_status.stop_clock

        @handler.run_report_unsafe(@run_status)
      end

      it 'only emits the run status metrics' do
        expect(a_request(:post, METRICS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] }
        )).to have_been_made.times(2)
      end

      it 'posts an event' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          query: { api_key: @handler.config[:api_key] },
          body: hash_including(msg_text: 'Chef was unable to complete a run, an error during compilation may have occurred.',
                               msg_title: "Chef failed during compile phase on #{@node.name} "),
        )).to have_been_made.times(1)
      end
    end
  end

  describe '#endpoints' do
    context 'with a basic config' do
      it 'returns the correct triplet' do
        handler = Chef::Handler::Datadog.new api_key: API_KEY, application_key: APPLICATION_KEY
        expect(handler.send(:endpoints)).to eq([["https://app.datadoghq.com", API_KEY, APPLICATION_KEY]])
      end
    end

    context 'with no url and two pairs of keys' do
      it 'returns the correct triplets' do
        triplets = [
          ["https://app.datadoghq.com", API_KEY, APPLICATION_KEY],
          ["https://app.datadoghq.com", 'api_key_2', 'app_key_2'],
          ["https://app.datadoghq.com", 'api_key_3', 'app_key_3']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             extra_endpoints: [{
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               api_key: triplets[2][1],
                                               application_key: triplets[2][2]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets)
      end
    end

    context 'with one url and two pairs of keys' do
      it 'returns the correct triplets' do
        triplets = [
          ['https://app.example.com', API_KEY, APPLICATION_KEY],
          ['https://app.example.com', 'api_key_2', 'app_key_2'],
          ['https://app.example.com', 'api_key_3', 'app_key_3']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             url: triplets[0][0],
                                             extra_endpoints: [{
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               api_key: triplets[2][1],
                                               application_key: triplets[2][2]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets)
      end
    end

    context 'with multiple urls' do
      it 'returns the correct triplets' do
        triplets = [
          ['https://app.datadoghq.com', 'api_key_2', 'app_key_2'],
          ['https://app.example.com', 'api_key_3', 'app_key_3'],
          ['https://app.example.com', 'api_key_4', 'app_key_4']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             url: triplets[0][0],
                                             extra_endpoints: [{
                                               url: triplets[1][0],
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               url: triplets[2][0],
                                               api_key: triplets[2][1],
                                               application_key: triplets[2][2]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets)
      end
    end

    context 'when missing application keys' do
      it 'returns available triplets' do
        triplets = [
          ["https://app.datadoghq.com", API_KEY, APPLICATION_KEY],
          ["https://app.datadoghq.com", 'api_key_2', 'app_key_2'],
          ["https://app.datadoghq.com", 'api_key_3', 'app_key_3']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             extra_endpoints: [{
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               api_key: triplets[2][1]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets[0..1])
      end
    end

    context 'when missing api keys' do
      it 'returns available triplets' do
        triplets = [
          ['https://app.datadoghq.com', 'api_key_2', 'app_key_2'],
          ['https://app.example.com', 'api_key_3', 'app_key_3'],
          ['https://app.example.com', 'api_key_4', 'app_key_4']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             url: triplets[0][0],
                                             extra_endpoints: [{
                                               url: triplets[1][0],
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               url: triplets[2][0],
                                               application_key: triplets[2][2]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets[0..1])
      end
    end

    context 'when using api url instead of url' do
      it 'returns available triplets' do
        triplets = [
          ['https://app.datadoghq.com', 'api_key_2' , 'app_key_2'],
          ['https://app.example.com', 'api_key_3', 'app_key_3'],
          ['https://app.example.com', 'api_key_4', 'app_key_4']
        ]
        handler = Chef::Handler::Datadog.new api_key: triplets[0][1],
                                             application_key: triplets[0][2],
                                             url: triplets[0][0],
                                             extra_endpoints: [{
                                               api_url: triplets[1][0],
                                               url: triplets[0][0],
                                               api_key: triplets[1][1],
                                               application_key: triplets[1][2]
                                             }, {
                                               api_url: triplets[2][0],
                                               url:triplets[0][0],
                                               api_key: triplets[2][1],
                                               application_key: triplets[2][2]
                                             }]
        expect(handler.send(:endpoints)).to eq(triplets)
      end
    end
  end

  context 'when reporting to multiple endpoints' do
    let(:api_key2) { 'api_key_example' }
    let(:application_key2) { 'application_key_example' }
    let(:base_url2) { 'https://app.example.com' }
    let(:events_endpoint2) { base_url2 + '/api/v1/events' }
    let(:host_tag_endpoint2) { base_url2 + '/api/v1/tags/hosts/' }
    let(:metrics_endpoint2) { base_url2 + '/api/v1/series' }
    let(:handler) do
      Chef::Handler::Datadog.new(api_key: API_KEY,
        application_key: APPLICATION_KEY,
        url: BASE_URL,
        extra_endpoints: [{
          api_key: api_key2,
          application_key: application_key2,
          url: base_url2
        }])
    end

    let(:dogs) do
      handler.instance_variable_get(:@dogs)
    end

    # Construct a good run_status
    before(:each) do
      dogs.each do |dog|
        # Define mock functions to avoid failures when connecting to the app.example.com endpoint
        allow(dog).to receive(:emit_point).and_return(true)
        allow(dog).to receive(:emit_event).and_return([200, "{'event': 'My event'}"])
        allow(dog).to receive(:update_tags).and_return([201, "Created"])
      end

      @node = Chef::Node.build('chef.handler.datadog.test')
      @node.send(:chef_environment, 'testing')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 5)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context
    end

    it 'should create multiple Dogapi clients' do
      expect(dogs.length).to eq(2)
    end

    context 'emits metrics' do
      it 'reports metrics to the first endpoint' do
        expect(dogs[0]).to receive(:emit_point).exactly(5).times

        handler.run_report_unsafe(@run_status)
      end

      it 'reports metrics to the second endpoint' do
        expect(dogs[1]).to receive(:emit_point).exactly(5).times

        handler.run_report_unsafe(@run_status)
      end
    end

    context 'emits events' do
      it 'posts an event to the first endpoint' do
        expect(dogs[0]).to receive(:emit_event).exactly(:once)

        handler.run_report_unsafe(@run_status)
      end

      it 'posts an event to the second endpoint' do
        expect(dogs[1]).to receive(:emit_event).exactly(:once)

        handler.run_report_unsafe(@run_status)
      end
    end

    context 'sets tags' do
      it 'puts the tags for the current node on the first endpoint' do
        expect(dogs[0]).to receive(:update_tags).exactly(:once)

        handler.run_report_unsafe(@run_status)
      end

      it 'puts the tags for the current node on the second endpoint' do
        expect(dogs[1]).to receive(:update_tags).exactly(:once)

        handler.run_report_unsafe(@run_status)
      end
    end
  end

    # TODO: test failures:
    # @run_status.exception = Exception.new('Boy howdy!')
end
