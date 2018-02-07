# Sequel::Elasticsearch

Sequel::Elasticsearch allows you to transparently mirror your database, or specific tables, to Elasticsearch. It's especially useful if you want the power of search through Elasticsearch, but keep the sanity and structure of a relational database.

[![Build Status](https://travis-ci.org/jrgns/sequel-elasticsearch.svg?branch=master)](https://travis-ci.org/jrgns/sequel-elasticsearch)
[![Maintainability](https://api.codeclimate.com/v1/badges/ff453fe81303a2fa7c02/maintainability)](https://codeclimate.com/github/jrgns/sequel-elasticsearch/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/ff453fe81303a2fa7c02/test_coverage)](https://codeclimate.com/github/jrgns/sequel-elasticsearch/test_coverage)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sequel-elasticsearch'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sequel-elasticsearch

## Usage

Require the gem with:

```ruby
require 'sequel/plugins/elasticsearch'
```

You'll need an Elasticsearch cluster to sync your data to. By default the gem will try to connect to `http://localhost:9200`. Set the `ELASTICSEARCH_URL` ENV variable to the URL of your cluster.

This is a Sequel plugin, so you can enable it DB wide:

```ruby
Sequel::Model.plugin :elasticsearch

```

Or per model:

```ruby
Sequel::Model.plugin Sequel::Elasticsearch

# or

class Node < Sequel::Model
  plugin :elasticsearch
end
```

There's a couple of options you can set:

```ruby
Sequel::Model.plugin :elasticsearch,
  elasticsearch: { log: true }, # Options to pass the the Elasticsearch ruby client
  index: 'all-my-data', # The index in which the data should be stored. Defaults to the table name associated with the model
  type: 'is-mine' # The type in which the data should be stored.
```

And that's it! Just transact as you normally would, and your records will be created and updated in the Elasticsearch cluster.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jrgns/sequel-elasticsearch.

Features that needs to be built:

- [x] An `es` method to search through the data on the cluster.
- [ ] Let `es` return an enumerator of `Sequel::Model` instances.
- [ ] A rake task to create or suggest mappings for a table.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

