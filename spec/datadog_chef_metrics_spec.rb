# encoding: utf-8
require 'spec_helper'

describe Chef::Handler::DatadogChefMetrics do

  let(:node) { Chef::Node.build('chef.handler.datadog.test-metrics') }
  let(:events) { Chef::EventDispatch::Dispatcher.new }

  let(:run_context) { Chef::RunContext.new(node, {}, events) }
  let(:run_status) { Chef::RunStatus.new(node, events) }

  let(:dog) { double('datadog-client').as_null_object }
  let(:hostname) { double('hostname') }

  let(:cache_filename) { '/tmp/chef-metrics-1420099200.json' }
  let(:cache_results) { double('cache_results') }
  let(:datadog_chef_metrics) {
    DatadogChefMetrics.new
    .with_dogapi_client(dog)
    .with_hostname(hostname)
    .with_run_status(run_status)
    .with_cache(cache_results)
  }

  describe '#initialize' do

    context 'sets instance variables' do
      let(:hostname) { "fake-hostname" }
      subject { datadog_chef_metrics.instance_variable_get("@hostname") }
      it { is_expected.to eq 'fake-hostname' }
    end

    it 'sets tmp file properly' do
      allow(Time).to receive(:now).and_return(Time.new('2015','01','01'))
      expect(datadog_chef_metrics.instance_variable_get('@cache_file_path')).to eq(cache_filename)
    end
  end

  describe '#write_detailed_resource_metrics' do
    let(:cache_file) { double('cache-file') }
    # there is no factory for those metrics thus crafting the fixtures manually
    let(:fake_metrics) { [
        { name: "chef.resources.convergence_time",
          value: 0.1,
          tags: "resource_name:whiskers cookbook:cookbook-test recipe:default"},
        {metric: "chef.resources.convergence_time",
         value: 0.2,
         tags: "resource_name:paws cookbook:cookbook-test recipe:default"}] }

    before(:each) do
      node.send(:chef_environment, 'testing')

      allow(Time).to receive(:now).and_return(Time.new('2015','01','01'))
      allow(run_status).to receive(:elapsed_time).and_return 2

      # dont' want it to iterate over any Chef::Resource list here, empty
      allow(run_status).to receive(:all_resources).and_return []

      # this short circuits the resource enumeration and parsing
      datadog_chef_metrics.details = fake_metrics
      # mock the file
      allow(File).to receive(:open).with(cache_filename, 'w+').and_yield(cache_file)
    end

    context 'caching enabled' do
      let(:cache_results) { true }
      after { datadog_chef_metrics.emit_to_datadog }
      subject { cache_file }
      it { is_expected.to receive(:write).with(JSON.dump(fake_metrics)) }
    end

    context 'caching disabled' do
      let(:cache_results) { false }
      before { datadog_chef_metrics.emit_to_datadog }
      subject { cache_file }
      it { is_expected.not_to receive(:write).with(JSON.dump(fake_metrics)) }
    end
  end
end
