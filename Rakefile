#!/usr/bin/env rake
# encoding: utf-8
require 'rubygems'
require 'bundler/gem_tasks'

require 'appraisal'
require 'rake/clean'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task :default => [:cops, :spec]

CLEAN.include(['coverage/', 'doc/', 'pkg/'])

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:cops)
