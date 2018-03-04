require 'rake'
require 'rake/tasklib'

include ::Rake::DSL if defined?(::Rake::DSL)

namespace :sequel do
  namespace :elasticsearch do
    desc 'Suggest Elasticsearch index mappings for a model'
    task :mappings, [:model] do |t, args|
      model = Object.const_get(args[:model])
      result = {}
      result[:properties] = model.db_schema.map do |k, v|
        [ k, Sequel::Plugins::Elasticsearch::Mappings.from_column(k, v) ]
      end.to_h
      p result
    end
  end
end
