module Sequel
  module Plugins
    module Elasticsearch
      class Result
        include Enumerable

        attr_reader :result, :scroll_id, :total, :took, :timed_out, :model

        def initialize(result, model = nil)
          return unless result && result['hits']

          @result = result
          @scroll_id = result['_scroll_id']
          @total = result['hits']['total']
          @timed_out = result['timed_out']
          @took = result['took']
          @model = model

          result['hits']['hits'] = result['hits']['hits'].map { |h| convert(h) }
        end

        def each
          return [] unless result['hits'] && result['hits']['hits'].count.positive?
          result['hits']['hits'].each { |h| yield h }
        end

        def method_missing(m, *args, &block)
          respond_to_missing?(m) ? result['hits']['hits'].send(m, *args, &block) : super
        end

        def respond_to_missing?(m, include_private = false)
          result['hits']['hits'].respond_to?(m, include_private) || super
        end

        private

        def convert(hit)
          return hit unless model
          source = hit['_source'].each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
          model.call source
        end
      end
    end
  end
end
