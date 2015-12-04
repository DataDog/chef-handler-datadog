# encoding: utf-8
require 'spec_helper'

describe Chef::Handler::DatadogChefMetrics do

  let(:node) { Chef::Node.build('chef.handler.datadog.test-metrics') }
  let(:events) { Chef::EventDispatch::Dispatcher.new }

  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:run_status) { Chef::RunStatus.new(node, events) }

  let(:dog) { double('datadog-client').as_null_object }
  let(:hostname) { double('hostname') }

  let(:log_filename) { '/tmp/chef-metrics-1420099200.json' }
  let(:log_results) { double('log-results') }
  let(:datadog_chef_metrics) {
    DatadogChefMetrics.new
    .with_dogapi_client(dog)
    .with_hostname(hostname)
    .with_run_status(run_status)
    .with_log(log_results)
  }

  describe '#initialize' do
    it 'sets tmp file properly' do
      expect(datadog_chef_metrics.log_file_path).to match(/chef-metrics/)
    end
  end

  describe '#write_detailed_resource_metrics' do
    let(:log_file) { double('log-file') }

    # there is no factory for those metrics thus crafting the fixtures manually
    let(:fake_metrics) { [
                           { name: "chef.resources.convergence_time",
                             value: 0.1,
                             tags: "resource_name:whiskers cookbook: recipe: updated:true resource_class:role"},
                           {metric: "chef.resources.convergence_time",
                            value: 0.2,
                            tags: "resource_name:paws cookbook: recipe: updated:true resource_class:role"}] }

    before(:each) do
      node.send(:chef_environment, 'testing')
      allow(run_status).to receive(:elapsed_time).and_return 2

      # dont' want it to iterate over any Chef::Resource list here, empty
      allow(run_status).to receive(:all_resources).and_return []

      # this short circuits the resource enumeration and parsing
      datadog_chef_metrics.details = fake_metrics
      # mock the file
      allow(File).to receive(:open).and_yield(log_file)
    end

    context 'caching enabled' do
      let(:log_results) { true }
      after { datadog_chef_metrics.emit_to_datadog }
      subject { log_file }
      it { is_expected.to receive(:write).with(JSON.dump(fake_metrics)) }
    end

    context 'caching disabled' do
      let(:log_results) { false }
      before { datadog_chef_metrics.emit_to_datadog }
      subject { log_file }
      it { is_expected.not_to receive(:write).with(JSON.dump(fake_metrics)) }
    end
  end

  describe '#collect_detailed_resource_metrics' do
    before(:each) do
      @node = Chef::Node.build('chef.handler.datadog.detailed-resource-metrics')
      @events = Chef::EventDispatch::Dispatcher.new
      @run_context = Chef::RunContext.new(@node, {}, @events)
      @run_status = Chef::RunStatus.new(@node, @events)

      @expected_time = Time.now
      allow(Time).to receive(:now).and_return(@expected_time, @expected_time + 2)
      @run_status.start_clock
      @run_status.stop_clock

      @run_status.run_context = @run_context

      # Set-up cookbook mapping, normally passed via @config[] Hash
      @resource_class_map = { :'cats-base' => 'base'}
    end


    context 'resource in the base class cookbook' do
      before do
        # Set-up resources
        all_resources = [
          Chef::Resource.new('whiskers'),
        ]
        all_resources[0].cookbook_name=:'cats-base'
        all_resources[0].updated_by_last_action(true)

        # Pass resources to the test, override @run_context
        @run_context.resource_collection.all_resources.replace(all_resources)

        @metrics = DatadogChefMetrics.new
        .with_run_status(@run_status)
        .with_resource_class_map(@resource_class_map)

      end

      it 'detects resource_class' do
        expect(@metrics).to receive(:resource_class_for).with(:'cats-base')
        @metrics.collect_detailed_resource_metrics
      end


      it 'populates details for base resource_class' do
        details = [
          {:name  => "chef.resources.convergence_time",
           :tags  => ["resource_name:whiskers",
                      "cookbook:cats-base",
                      "recipe:",
                      "updated:true",
                      "resource_class:base"],
           :value => 0}]

        @metrics.collect_detailed_resource_metrics
        expect(@metrics.details).to eq details
      end
    end

    context 'resource in not base class cookbook' do
      before do
        # Set-up resources
        all_resources = [
          Chef::Resource.new('whiskers'),
        ]
        all_resources[0].cookbook_name=:'cats-not-base-cookbook'
        all_resources[0].updated_by_last_action(true)

        # Pass resources to the test, override @run_context
        @run_context.resource_collection.all_resources.replace(all_resources)

        @metrics = DatadogChefMetrics.new
        .with_run_status(@run_status)
        .with_resource_class_map(@resource_class_map)

      end

      it 'populates details for default (role) resource_class' do
        details = [
          {:name  => "chef.resources.convergence_time",
           :tags  => ["resource_name:whiskers",
                      "cookbook:cats-not-base-cookbook",
                      "recipe:",
                      "updated:true",
                      "resource_class:role"],
           :value => 0}]

        @metrics.collect_detailed_resource_metrics
        expect(@metrics.details).to eq details
      end
    end
  end
end
