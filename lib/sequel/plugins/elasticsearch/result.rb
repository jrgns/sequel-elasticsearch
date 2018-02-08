module Sequel
  module Plugins
    module Elasticsearch
      class Result
        include Enumerable

        attr_reader :results, :scroll_id, :total, :took, :timed_out, :model

        def initialize(results, model = nil)
          return unless results && results['hits']
          @results = results
          @scroll_id = results['_scroll_id']
          @total = results['hits']['total']
          @timed_out = results['timed_out']
          @took = results['took']
          @model = model
        end

        def each
          return [] unless results['hits'] && results['hits']['hits']
          results['hits']['hits'].each do |h|
            yield convert(h)
          end
          # TODO: Use the scroll id to get more if needed
          # We will need access to the client, somehow...
        end

        def all
          results['hits']['hits'].map do |h|
            convert(h)
          end
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
