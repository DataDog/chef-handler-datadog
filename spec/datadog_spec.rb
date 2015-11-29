# encoding: utf-8
require 'spec_helper'

describe Chef::Handler::Datadog, :vcr => :new_episodes do
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


  let(:cache_resource_details) { false }

  before(:each) do
    @handler = Chef::Handler::Datadog.new(
      :api_key         => API_KEY,
      :application_key => APPLICATION_KEY,
      :cache_resource_details => cache_resource_details,
    )
  end


  describe 'initialize' do
    it 'should allow config hash to have string keys' do
      Chef::Handler::Datadog.new(
        'api_key'         => API_KEY,
        'application_key' => APPLICATION_KEY,
        'cache_resource_details' => cache_resource_details,
      )
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
          :query => { 'api_key' => @handler.config[:api_key] },
          :body => hash_including(:series))).to have_been_made.times(1)
      end
    end

    context 'emits events' do
      it 'posts an event' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          :query => { 'api_key' => @handler.config[:api_key] },
          :body => hash_including(:msg_text => 'Chef updated 0 resources out of 0 resources total.'),
          :body => hash_including(:msg_title => "Chef completed in 5 seconds on #{@node.name} "),
          :body => hash_including(:tags => ['env:testing']),
        )).to have_been_made.times(1)
      end

      it 'sets priority correctly' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          :query => { 'api_key' => @handler.config[:api_key] },
          :body => hash_including(:priority => 'low'),
        )).to have_been_made.times(1)
      end
    end

    context 'sets tags' do
      it 'puts the tags for the current node' do
        # We no longer need to query the tag api for current tags,
        # rather udpate only the tags for the designated source type
        expect(a_request(:get, HOST_TAG_ENDPOINT + @node.name).with(
          :query => { 'api_key' => @handler.config[:api_key],
                      'application_key' => @handler.config[:application_key] },
        )).to have_been_made.times(0)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          :query => { 'api_key' => @handler.config[:api_key],
                      'application_key' => @handler.config[:application_key],
                      'source' => 'chef' },
          :body => { 'tags' => ['env:testing'] },
        )).to have_been_made.times(1)
      end
    end
  end

  describe 'reports correct hostname on an ec2 node' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-ec2')
      @node.send(:chef_environment, 'testing')

      @node.automatic_attrs['ec2'] = { :instance_id => 'i-123456' }

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
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => 'Chef completed in 5 seconds on i-123456 '),
        :body => hash_including(:host => 'i-123456'),
      )).to have_been_made.times(1)
    end

    it 'uses the instance id when config is specified' do
      @handler.config[:use_ec2_instance_id] = true
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => 'Chef completed in 5 seconds on i-123456 '),
        :body => hash_including(:host => 'i-123456'),
      )).to have_been_made.times(1)
    end

    it 'does not use the instance id when config specified to false' do
      @handler.config[:use_ec2_instance_id] = false
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => "Chef completed in 5 seconds on #{@node.name} "),
        :body => hash_including(:host => @node.name),
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
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => "Chef completed in 5 seconds on #{@node.name}"),
        :body => hash_including(:host => @node.name),
      )).to have_been_made.times(1)
    end

    it 'uses the specified hostname when provided' do
      @handler.config[:hostname] = 'my-imaginary-hostname.local'
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => 'Chef completed in 5 seconds on my-imaginary-hostname.local'),
        :body => hash_including(:host => 'my-imaginary-hostname.local'),
      )).to have_been_made.times(1)
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
        @node.normal.tags = ['the_one_and_only']
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          :query => { 'api_key' => @handler.config[:api_key],
                      'application_key' => @handler.config[:application_key],
                      'source' => 'chef' },
          :body => hash_including(:tags => [
            'env:hostile', 'role:highlander', 'tag:the_one_and_only'
            ]),
        )).to have_been_made.times(1)
      end
    end

    describe 'when unspecified' do
      it 'sets role, env and nothing else' do
        @handler.run_report_unsafe(@run_status)

        expect(a_request(:put, HOST_TAG_ENDPOINT + @node.name).with(
          :query => { 'api_key' => @handler.config[:api_key],
                      'application_key' => @handler.config[:application_key],
                      'source' => 'chef' },
          :body => hash_including(:tags => [
            'env:hostile', 'role:highlander'
            ]),
        )).to have_been_made.times(1)
      end
    end
  end

  describe 'handles no application_key' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-noapp')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')
      @node.normal.tags = ['the_one_and_only']

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
      @handler.config[:application_key] = nil

      # TODO: figure out how to capture output of Chef::Log
      # Run the report, catch the error
      expect { @handler.run_report_unsafe(@run_status) }.to raise_error
    end
  end

  describe 'failed Chef run' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-failed')

      @node.send(:chef_environment, 'hostile')
      @node.send(:run_list, 'role[highlander]')
      @node.normal.tags = ['the_one_and_only']

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
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_title => "Chef failed in 2 seconds on #{@node.name} "),
      )).to have_been_made.times(1)
    end

    it 'sets priority correctly' do
      expect(a_request(:post, EVENTS_ENDPOINT).with(
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:alert_type => 'success'),
        :body => hash_including(:priority => 'normal'),
      )).to have_been_made.times(1)
    end

    it 'sets alert handles when specified' do
      @handler.config[:notify_on_failure] = ['@alice', '@bob']
      @handler.run_report_unsafe(@run_status)

      expect(a_request(:post, EVENTS_ENDPOINT).with(
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => /Alerting: @alice @bob/
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
        :query => { 'api_key' => @handler.config[:api_key] },
        :body => hash_including(:msg_text => 'Chef updated 1 resources out of 2 resources total.'),
        :body => hash_including(:msg_title => "Chef completed in 8 seconds on #{@node.name} "),
      )).to have_been_made.times(1)
    end
  end

  describe 'resources' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.test-resources')
      @node.send(:chef_environment, 'resources')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)
    end

    context 'failure during compile phase' do
      before(:each) do
        @handler.run_report_unsafe(@run_status)
      end

      it 'does not emit metrics' do
        expect(a_request(:post, METRICS_ENDPOINT).with(
          :query => { 'api_key' => @handler.config[:api_key] }
        )).to_not have_been_made
      end

      it 'posts an event' do
        expect(a_request(:post, EVENTS_ENDPOINT).with(
          :query => { 'api_key' => @handler.config[:api_key] },
          :body => hash_including(:msg_text => 'Chef was unable to complete a run, an error during compilation may have occured.'),
          :body => hash_including(:msg_title => "Chef failed during compile phase on #{@node.name} "),
        )).to have_been_made.times(1)
      end
    end
  end

  describe 'detailed metrics' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.detailed-resource-metrics')

      @node.send(:chef_environment, 'testing')
      @node.send(:run_list, 'role[highlander]')
      @node.normal.tags = ['the_one_and_only'] # TODO: check what tags are being passed

      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      allow_any_instance_of(Chef::ResourceResolver).to receive(:resolve).and_return(Chef::Resource::Package)

      all_resources = [
        Chef::ResourceBuilder.new(name: 'whiskers',
                                  type: 'package',
                                  cookbook_name: 'cookbook-test',
                                  recipe_name: 'default',
                                  run_context: @run_context ).build,
        Chef::ResourceBuilder.new(name: 'paws',
                                  type: 'package',
                                  cookbook_name: 'cookbook-test',
                                  recipe_name: 'default',
                                  run_context: @run_context ).build,
        ]

      all_resources.map { |r| r.updated_by_last_action(true) }
      @run_context.resource_collection.all_resources.replace(all_resources)

      @all_resources_metrics_details = [
        {:name=>"chef.resources.convergence_time",
        :tags=>"resource_name:whiskers cookbook:cookbook-test recipe:default",
        :value=>0},
        {:name=>"chef.resources.convergence_time",
        :tags=>"resource_name:paws cookbook:cookbook-test recipe:default",
        :value=>0}]

      # freezing time, want to asser the exact payload
      @expected_time = Time.new('2015','01','01')
      @finish_time = @expected_time + 2
      allow(Time).to receive(:now).and_return(@expected_time, @finish_time)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context
    end

    context "collects detailed metrics" do
      before { @handler.run_report_unsafe(@run_status) }
      subject { @handler.metrics.details }
      it { is_expected.to eq @all_resources_metrics_details }
    end

    context 'saves resource details' do
      let(:cache_file) { double('cache-file') }
      let(:cache_filename) { "/tmp/chef-metrics-#{@finish_time.to_i}.json" }

      context 'cache enabled' do
        let(:cache_resource_details) { true }
        before do
          allow(File).to receive(:open).and_call_original
          allow(File).to receive(:open).with(cache_filename, 'w+').and_yield(cache_file)
        end
        subject { cache_file }
        it { is_expected.to receive(:write).with(JSON.dump(@all_resources_metrics_details)) }
        after { @handler.run_report_unsafe(@run_status) }
      end

      context 'cache disabled' do
        let(:cache_resource_details) { false }
        before do
         allow(File).to receive(:open).and_call_original
         allow(File).to receive(:open).with(cache_filename, 'w+').and_yield(cache_file)
         @handler.run_report_unsafe(@run_status)
        end
        subject { cache_file }
        it { is_expected.not_to receive(:write) }
      end
    end

    context "sends detailed metrics" do
      let(:request_body) { { series: [] } }
      before { @handler.run_report_unsafe(@run_status) }
      it 'posts detailed metrics' do
        [{metric: "chef.resources.convergence_time",
          points: [[1420099202,0.0]],
          type: "gauge",
          host: "chef.handler.datadog.detailed-resource-metrics",
          device: nil,
          tags: "resource_name:whiskers cookbook:cookbook-test recipe:default"},
         {metric: "chef.resources.convergence_time",
          points: [[1420099202,0.0]],
          type: "gauge",
          host: "chef.handler.datadog.detailed-resource-metrics",
          device: nil,
          tags: "resource_name:paws cookbook:cookbook-test recipe:default"},
         {metric: "chef.resources.total",
          points: [[1420099202,2.0]],
          type: "gauge",
          host: "chef.handler.datadog.detailed-resource-metrics",
          device: nil},
         {metric: "chef.resources.updated",
          points: [[1420099202,2.0]],
          type: "gauge",
          host: "chef.handler.datadog.detailed-resource-metrics",
          device: nil},
         {metric: "chef.resources.elapsed_time",
          points: [[1420099202,2.0]],
          type: "gauge",
          host: "chef.handler.datadog.detailed-resource-metrics",
          device: nil}].each { |b| request_body[:series] << b }

       expect(a_request(:post, METRICS_ENDPOINT).with(
          :query => { 'api_key' => @handler.config[:api_key] },
          :body => request_body)).to have_been_made.times(1)
       end
    end
  end

    # TODO: test failures:
    # @run_status.exception = Exception.new('Boy howdy!')
end
