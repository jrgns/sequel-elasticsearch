module Sequel
  module Plugins
    module Elasticsearch
      # A wrapper around Elasticsearch results to make it behave more like a Sequel Dataset.
      class Result
        include Enumerable

        # The original result returned from the Elasticsearch client
        attr_reader :result
        # The scroll id, if set, from the result
        attr_reader :scroll_id
        # The total number of documents in the Elasticsearch result
        attr_reader :total
        # The time, in miliseconds, the Elasticsearch call took to complete
        attr_reader :took
        # If the Elasticsearch call timed out or note
        attr_reader :timed_out
        # The model class associated with this result
        attr_reader :model

        # Initialize the Result
        #
        # * +result+ The result returns from the Elasticsearch client / +.es+ call.
        # * +model+ The model class on which the results should be applied.
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

        # Each implementation for the Enumerable. Yield each element in the +result['hits']['hits']+ array.
        def each
          return [] unless result['hits'] && result['hits']['hits'].count.positive?
          result['hits']['hits'].each { |h| yield h }
        end

        # Send all undefined methods to the +result['hits']['hits']+ array.
        def method_missing(m, *args, &block)
          respond_to_missing?(m) ? result['hits']['hits'].send(m, *args, &block) : super
        end

        # Send all undefined methods to the +result['hits']['hits']+ array.
        def respond_to_missing?(m, include_private = false)
          result['hits']['hits'].respond_to?(m, include_private) || super
        end

        private

        # Convert an Elasticsearch hit to a Sequel::Model
        def convert(hit)
          return hit unless model
          source = hit['_source'].each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
          model.call source
        end
      end
    end
  end
end
