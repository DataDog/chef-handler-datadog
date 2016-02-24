#!/usr/bin/env rake
# encoding: utf-8
require 'rubygems'
require 'bundler/gem_tasks'

require 'rake/clean'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

task default: [:cops, :spec]

CLEAN.include(['coverage/', 'doc/', 'pkg/'])

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:cops)

namespace :dev do
  task :setup do
    cp '.env.example', '.env'
    Rake::Task[:default].invoke
  end
end
