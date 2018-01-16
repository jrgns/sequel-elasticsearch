ENV['RACK_ENV'] ||= 'test'
ENV['DATABASE_URL'] ||= 'sqlite::memory:'
ENV['ELASTICSEARCH_URL'] ||= 'http://localhost:9200'

require 'sequel'
require 'webmock/rspec'
require 'simplecov'
SimpleCov.start

DB = Sequel.connect ENV['DATABASE_URL']

RSpec.configure do |config|
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
end
