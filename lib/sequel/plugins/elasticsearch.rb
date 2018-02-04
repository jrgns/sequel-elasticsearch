require 'elasticsearch'

module Sequel
  module Plugins
    module Elasticsearch
      def self.apply(model, _opts = OPTS)
        model.instance_variable_set(:@elasticsearch_opts, {})
        model.instance_variable_set(:@elasticsearch_index, nil)
        model.instance_variable_set(:@elasticsearch_type, 'sync')
        model
      end

      def self.configure(model, opts = OPTS)
        model.elasticsearch_opts = opts[:elasticsearch] || {}
        model.elasticsearch_index = (opts[:index] || model.table_name).to_sym
        model.elasticsearch_type = (opts[:type] || :sync).to_sym
        model
      end

      module ClassMethods
        attr_accessor :elasticsearch_opts, :elasticsearch_index, :elasticsearch_type

        def es_client
          @es_client = ::Elasticsearch::Client.new elasticsearch_opts
        end

        def es!(query = '', opts = {})
          opts = {
            index: elasticsearch_index,
            type: elasticsearch_type
          }.merge(opts)
          query.is_a?(String) ? opts[:q] = query : opts[:body] = query
          enumerate es_client.search(opts)
        end

        def enumerate(results)
          return [] if results['hits']['total'] == 0
          results['hits']['hits'].map { |h| self.call h['_source'] }
        end

        def es(query = '', opts = {})
          call_es { es! query, opts }
        end

        def call_es
          yield
        rescue ::Elasticsearch::Transport::Transport::Errors::NotFound, ::Elasticsearch::Transport::Transport::Error => e
          db.loggers.first.warn e if db.loggers.count.positive?
          nil
        rescue Faraday::ConnectionFailed => e
          db.loggers.first.warn e if db.loggers.count.positive?
          nil
        end
      end

      module InstanceMethods
        def after_create
          super
          self.class.call_es { index_document }
        end

        def after_destroy
          super
          self.class.call_es { destroy_document }
        end

        def after_update
          super
          self.class.call_es { index_document }
        end

        def es_client
          self.class.es_client
        end

        private

        def document_id
          doc_id = pk
          doc_id = doc_id.join('_') if doc_id.is_a? Array
          doc_id
        end

        def document_path
          {
            index: self.class.elasticsearch_index,
            type: self.class.elasticsearch_type,
            id: document_id
          }
        end

        def index_document
          params = document_path
          params[:body] = values
          es_client.index params
        end

        def destroy_document
          es_client.delete document_path
        end
      end
    end
  end
end
