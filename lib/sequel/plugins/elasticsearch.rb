# frozen_string_literal: true

require 'elasticsearch'
require 'sequel/plugins/elasticsearch/result'

# Sequel: The Database Toolkit for Ruby
module Sequel
  # Sequel Plugins - http://sequel.jeremyevans.net/plugins.html
  module Plugins
    # The Sequel::Elasticsearch model plugin
    #
    # @example Simple usage
    #
    #     require 'sequel-elasticsearch'
    #     Document.plugin Sequel::Elasticsearch
    #     Document.es('test')
    #
    module Elasticsearch
      # Apply the plugin to the specified model
      def self.apply(model, _opts = OPTS)
        model
      end

      # Configure the plugin
      def self.configure(model, opts = OPTS)
        model.elasticsearch_opts = opts[:elasticsearch] || {}
        model.elasticsearch_index = (opts[:index] || model.table_name.to_s.downcase).to_sym
        model.elasticsearch_type = opts[:type]&.to_sym
        model
      end

      # The class methods that will be added to the Sequel::Model
      module ClassMethods
        # The extra options that will be passed to the Elasticsearch client.
        attr_accessor :elasticsearch_opts
        # The Elasticsearch index to which the documents will be written.
        attr_accessor :elasticsearch_index
        # The Elasticsearch type to which the documents will be written.
        attr_accessor :elasticsearch_type

        # Return the Elasticsearch client used to communicate with the cluster.
        def es_client
          @es_client = ::Elasticsearch::Client.new elasticsearch_opts
        end

        # Execute a search on the Model's Elasticsearch index without catching Errors.
        def es!(query = '', opts = {})
          opts = {
            index: elasticsearch_index,
            type: elasticsearch_type
          }.merge(opts)
          query.is_a?(String) ? opts[:q] = query : opts[:body] = query
          Result.new es_client.search(opts), self
        end

        # Fetch the next page in a scroll without catching Errors.
        def scroll!(scroll_id, duration)
          scroll_id = scroll_id.scroll_id if scroll_id.is_a? Result
          return nil unless scroll_id

          Result.new es_client.scroll(scroll_id: scroll_id, scroll: duration), self
        end

        # Execute a search or a scroll on the Model's Elasticsearch index.
        # This method is "safe" in that it will catch the more common Errors.
        def es(query = '', opts = {})
          call_es { query.is_a?(Result) ? scroll!(query, opts) : es!(query, opts) }
        end

        # Wrapper method in which error handling is done for Elasticsearch calls.
        def call_es
          yield
        rescue ::Elasticsearch::Transport::Transport::Errors::NotFound,
               ::Elasticsearch::Transport::Transport::Error,
               Faraday::ConnectionFailed => e
          db.loggers.first.warn e if db.loggers.count.positive?
          nil
        end

        # Import the whole dataset into Elasticsearch.
        #
        # This assumes that a template that covers all the possible index names
        # have been created. See +timestamped_index+ for examples of the indices
        # that will be created.
        #
        # This adds or updates records to the last index created by this utility.
        # Use the +reindex!+ method to create a completely new index and alias.
        def import!(index: nil, dataset: nil, batch_size: 100)
          dataset ||= self.dataset
          index_name = index || last_index || elasticsearch_index

          # Index all the documents
          body = []
          dataset.each_page(batch_size) do |ds|
            body = []
            ds.all.each do |row|
              print '.'
              body << { update: import_object(index_name, row) }
            end
            puts '/'
            es_client.bulk body: body
            body = nil
          end
        end

        def import_object(idx, row)
          val = {
            _index: idx,
            _id: row.document_id,
            data: { doc: row.as_indexed_json, doc_as_upsert: true }
          }
          val[:_type] = elasticsearch_type if elasticsearch_type
          val
        end

        # Creates a new index in Elasticsearch from the specified dataset, as
        # well as an alias to the new index.
        #
        # See the documentation on +import!+ for more details.
        def reindex!(index: nil, dataset: nil, batch_size: 100)
          index_name = index || timestamped_index
          import!(index: index_name, dataset: dataset, batch_size: batch_size)

          # Create an alias to the newly created index
          alias_index(index_name)
        end

        # Remove previous aliases and point the `elasticsearch_index` to the new index.
        def alias_index(new_index)
          es_client.indices.update_aliases body: {
            actions: [
              { remove: { index: "#{elasticsearch_index}*", alias: elasticsearch_index } },
              { add: { index: new_index, alias: elasticsearch_index } }
            ]
          }
        end

        # Find the last created index that matches the specified index name.
        def last_index
          es_client.indices.get_alias(name: elasticsearch_index)&.keys&.sort&.first
        rescue ::Elasticsearch::Transport::Transport::Errors::NotFound
          nil
        end

        # Generate a timestamped index name.
        # This will use the current timestamp to construct index names like this:
        #
        #    base-name-20191004.123456
        def timestamped_index
          time_str = Time.now.strftime('%Y%m%d.%H%M%S') # TODO: Make the format configurable
          "#{elasticsearch_index}-#{time_str}".to_sym
        end
      end

      # The instance methods that will be added to the Sequel::Model
      module InstanceMethods
        def elasticsearch_index
          self.class.elasticsearch_index
        end

        def elasticsearch_type
          self.class.elasticsearch_type
        end

        # Sequel::Model after_create hook to add the new record to the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_create
          super
          self.class.call_es { _index_document }
        end

        # Sequel::Model after_destroy hook to remove the record from the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_destroy
          super
          self.class.call_es { _destroy_document }
        end

        # Sequel::Model after_update hook to update the record in the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_update
          super
          self.class.call_es { _index_document }
        end

        # Return the Elasticsearch client used to communicate with the cluster.
        def es_client
          self.class.es_client
        end

        # Mirror the Elasticsearch Rails plugin. Use this to override what data
        # is sent to Elasticsearch
        def as_indexed_json
          indexed_values
        end

        # Internal reference for index_document. Override this for alternate
        # implementations of indexing the document.
        def _index_document(opts = {})
          index_document(opts)
        end

        # Create or update the document on the Elasticsearch cluster.
        def index_document(opts = {})
          params = document_path(opts)
          params[:body] = as_indexed_json
          es_client.index params
        end

        # Internal reference for destroy_document. Override this for alternate
        # implementations of removing the document.
        def _destroy_document(opts = {})
          destroy_document(opts)
        end

        # Remove the document from the Elasticsearch cluster.
        def destroy_document(opts = {})
          es_client.delete document_path(opts)
        end

        # Determine the complete path to a document (/index/type/id) in the Elasticsearch cluster.
        def document_path(opts = {})
          {
            index: opts.delete(:index) || elasticsearch_index,
            type: opts.delete(:type) || elasticsearch_type,
            id: opts.delete(:id) || document_id
          }
        end

        # Determine the ID to be used for the document in the Elasticsearch cluster.
        # It will join the values of a multi field primary key with an underscore.
        def document_id
          doc_id = pk
          doc_id = doc_id.join('_') if doc_id.is_a? Array
          doc_id
        end

        private

        # Values to be indexed
        def indexed_values
          # TODO: Deprecate this method in favour of as_indexed_json
          values.each_key { |k| values[k] = values[k].strftime('%FT%T%:z') if values[k].is_a?(Time) }
        end
      end
    end
  end
end
