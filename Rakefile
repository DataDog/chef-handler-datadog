#!/usr/bin/env rake
# encoding: utf-8
require 'rubygems'
require 'bundler/gem_tasks'

require 'rspec/core/rake_task'
require 'tailor/rake_task'

task :default => :test

RSpec::Core::RakeTask.new(:spec)

Tailor::RakeTask.new do |task|
  task.file_set('lib/**/*.rb', "code") do |style|
    style.max_line_length 160, :level => :warn
  end
end
