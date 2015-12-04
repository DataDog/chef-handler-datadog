# encoding: utf-8
require 'spec_helper'

describe Chef::Handler::DatadogChefMetrics do

  let(:node) { Chef::Node.build('chef.handler.datadog.test-metrics') }
  let(:events) { Chef::EventDispatch::Dispatcher.new }

  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:run_status) { Chef::RunStatus.new(node, events) }

  let(:dog) { double('datadog-client').as_null_object }
  let(:hostname) { double('hostname') }

  let(:datadog_chef_metrics) {
    DatadogChefMetrics.new
    .with_dogapi_client(dog)
    .with_hostname(hostname)
    .with_run_status(run_status)
  }

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
        expect(@metrics).to receive(:resource_class).with(:'cats-base')
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
