require 'elasticsearch'

module Sequel
  module Plugins
    module Elasticsearch
      def self.apply(model, opts=OPTS)
        model.instance_variable_set(:@elasticsearch_opts, {})
        model.instance_variable_set(:@elasticsearch_index, nil)
        model.instance_variable_set(:@elasticsearch_type, 'sync')
      end

      def self.configure(model, opts=OPTS)
        model.elasticsearch_opts = opts[:elasticsearch] || {}
        model.elasticsearch_index = opts[:index] || model.table_name
        model.elasticsearch_type = opts[:type] || 'sync'
      end

      module ClassMethods
        attr_accessor :elasticsearch_opts, :elasticsearch_index, :elasticsearch_type
      end

      module InstanceMethods
        def after_create
          super
          index_document
        end

        def after_destroy
          super
          destroy_document
        end

        def after_update
          super
          index_document
        end

        private

        def es_client
          @es_client = ::Elasticsearch::Client.new self.class.elasticsearch_opts
        end

        def document_id
          doc_id = pk
          doc_id = doc_id.join('_') if doc_id.is_a? Array
          doc_id
        end

        def document_path
          {
            index: self.class.table_name,
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
