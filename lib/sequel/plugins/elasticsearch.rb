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
        model.instance_variable_set(:@elasticsearch_opts, {})
        model.instance_variable_set(:@elasticsearch_index, nil)
        model.instance_variable_set(:@elasticsearch_type, '_doc')
        model
      end

      # Configure the plugin
      def self.configure(model, opts = OPTS)
        model.elasticsearch_opts = opts[:elasticsearch] || {}
        model.elasticsearch_index = (opts[:index] || model.table_name).to_sym
        model.elasticsearch_type = (opts[:type] || :_doc).to_sym
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
        #
        # TODO: Bulk batches
        def import!(index: nil, dataset: nil)
          dataset ||= self.dataset
          index_name = index || last_index

          # Index all the documents
          body = []
          dataset.all.each do |row|
            body << {
              update: {
                _index: index_name,
                _type: elasticsearch_type,
                _id: row.document_id,
                data: { doc: row.indexed_values, doc_as_upsert: true }
              }
            }
            next unless body.count >= 100

            es_client.bulk body: body
            body = []
          end
          es_client.bulk body: body if body.count.positive?
        end

        # Creates a new index in Elasticsearch from the specified dataset, as
        # well as an alias to the new index.
        #
        # See the documentation on +import!+ for more details.
        def reindex!(index: nil, dataset: nil)
          index_name = index || timestamped_index
          import!(index: index_name, dataset: dataset)

          # Create an alias to the newly created index
          es_client.indices.update_aliases body: {
            actions: [
              { remove: { index: "#{elasticsearch_index}*", alias: elasticsearch_index } },
              { add: { index: index_name, alias: elasticsearch_index } }
            ]
          }
        end

        # Find the last created index that matches the specified index name.
        def last_index
          es_client.indices.get_alias(name: elasticsearch_index)&.keys&.sort&.first
        end

        # Generate a timestamped index name according to the environment.
        # This will use the +APP_ENV+ ENV variable and a timestamp to construct
        # index names like this:
        #
        #    base-name-staging-20191004.123456 # This is a staging index
        #    base-name-20191005.171213 # This is a production index
        #
        def timestamped_index
          time_str = Time.now.strftime('%Y%m%d.%H%M%S')
          env_str = ENV['APP_ENV'] == 'production' ? nil : ENV['APP_ENV']
          [elasticsearch_index, env_str, time_str].compact.join('-')
        end
      end

      # The instance methods that will be added to the Sequel::Model
      module InstanceMethods
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
          params[:body] = indexed_values
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
            index: opts.delete(:index) || self.class.elasticsearch_index,
            type: opts.delete(:type) || self.class.elasticsearch_type,
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
