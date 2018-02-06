module Sequel
  module Plugins
    module Elasticsearch
      class Result
        include Enumerable

        attr_reader :results, :scroll_id, :total, :took, :timed_out

        def initialize(results)
          return unless results && results['hits']
          @results = results
          @scroll_id = results['_scroll_id']
          @total = results['hits']['total']
          @timed_out = results['timed_out']
          @took = results['took']
        end

        def each
          return [] unless results['hits'] && results['hits']['hits']
          results['hits']['hits'].each { |h| yield h }
          # TODO: Use the scroll id to get more if needed
          # We will need access to the client, somehow...
        end
      end
    end
  end
end
