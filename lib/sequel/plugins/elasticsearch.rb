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

        # Import the whole dataset into Elasticsearch
        def import!
        end
      end

      # The instance methods that will be added to the Sequel::Model
      module InstanceMethods
        # Sequel::Model after_create hook to add the new record to the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_create
          super
          self.class.call_es { index_document }
        end

        # Sequel::Model after_destroy hook to remove the record from the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_destroy
          super
          self.class.call_es { destroy_document }
        end

        # Sequel::Model after_update hook to update the record in the Elasticsearch index.
        # It's "safe" in that it won't raise an error if it fails.
        def after_update
          super
          self.class.call_es { index_document }
        end

        # Return the Elasticsearch client used to communicate with the cluster.
        def es_client
          self.class.es_client
        end

        def as_indexed_json
          indexed_values
        end

        # Create or update the document on the Elasticsearch cluster.
        def index_document
          params = document_path
          params[:body] = indexed_values
          es_client.index params
        end

        # Remove the document from the Elasticsearch cluster.
        def destroy_document
          es_client.delete document_path
        end

        # Determine the complete path to a document (/index/type/id) in the Elasticsearch cluster.
        def document_path
          {
            index: self.class.elasticsearch_index,
            type: self.class.elasticsearch_type,
            id: document_id
          }
        end

        private

        # Determine the ID to be used for the document in the Elasticsearch cluster.
        # It will join the values of a multi field primary key with an underscore.
        def document_id
          doc_id = pk
          doc_id = doc_id.join('_') if doc_id.is_a? Array
          doc_id
        end

        # Values to be indexed
        def indexed_values
          # TODO: Deprecate this method in favour of as_indexed_json
          values.each_key { |k| values[k] = values[k].strftime('%FT%T%:z') if values[k].is_a?(Time) }
        end
      end
    end
  end
end
