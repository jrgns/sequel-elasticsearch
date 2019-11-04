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
Document.plugin Sequel::Elasticsearch

# or

class Document < Sequel::Model
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

### Searching

Your model is now searchable through Elasticsearch. Just pass down a string that's parsable as a [query string query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html).

```ruby
Document.es('title:Sequel')
Document.es('title:Sequel AND body:Elasticsearch')
```

The result from the `es` method is an enumerable containing `Sequel::Model` instances of your model:

```ruby
results = Document.es('title:Sequel')
results.each { |e| p e }
# Outputs
# #<Document @values={:id=>1, :title=>"Sequel", :body=>"Document 1"}>
# #<Document @values={:id=>2, :title=>"Sequel", :body=>"Document 2"}>
```

The result also contains the meta info about the Elasticsearch query result:

```ruby
results = Document.es('title:Sequel')
p results.count # The number of documents included in this result
p results.total # The total number of documents in the index that matches the search
p results.timed_out # If the search timed out or not
p results.took # How long, in miliseconds the search took
```

You can also use the scroll API to search and fetch large datasets:

```ruby
# Get a dataset that will stay consistent for 5 minutes and extend that time with 1 minute on every iteration
scroll = Document.es('test', scroll: '5m')
p scroll_id # Outputs the scroll_id for this specific scrolling snapshot
puts "Found #{scroll.count} of #{scroll.total} documents"
scroll.each { |e| p e }
while (scroll = Document.es(scroll, scroll: '1m')) && scroll.empty? == false do
  puts "Found #{scroll.count} of #{scroll.total} documents"
  scroll.each { |e| p e }
end
```

### Import

You can import the whole dataset, or specify a dataset to be imported. This will create a new, timestamped index for your dataset, and import all the records from that dataset into the index. An alias will be created (or updated) to point to the newly created index.

```ruby
Document.import! # Import all the Document records. Use the default settings.

Document.import!(dataset: Document.where(active: true)) # Import all the active Document records

Document.import!(
    index: 'active-documents', # Use the active-documents index
    dataset: Document.where(active: true), # Only index active documents
    batch_size: 20 # Send documents to Elasticsearch in batches of 20 records
)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jrgns/sequel-elasticsearch.

Features that needs to be built:

- [x] An `es` method to search through the data on the cluster.
- [x] Let `es` return an enumerator of `Sequel::Model` instances.
- [ ] A rake task to create or suggest mappings for a table.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

