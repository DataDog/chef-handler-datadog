#!/usr/bin/env rake
# encoding: utf-8
require 'rubygems'
require 'bundler/gem_tasks'

require 'appraisal'
require 'rake/clean'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task :default => :test

RSpec::Core::RakeTask.new(:spec)

Rubocop::RakeTask.new(:cops)
