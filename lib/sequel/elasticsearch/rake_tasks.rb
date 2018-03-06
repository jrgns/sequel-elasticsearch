require 'rake'
require 'rake/tasklib'

include ::Rake::DSL if defined?(::Rake::DSL)

namespace :sequel do
  namespace :elasticsearch do
    desc 'Create / Update Elasticsearch index mappings for a model'
    task :mappings, [:model] do |t, args|
      model = Object.const_get(args[:model])
      result = {}
      result[:properties] = model.db_schema.map do |k, v|
        [ k, Sequel::Plugins::Elasticsearch::Mappings.from_column(k, v) ]
      end.to_h
      begin
        model.es_client.indices.create index: model.elasticsearch_index,
                                       type: model.elasticsearch_type,
                                       body: {
                                         mappings: {
                                          model.elasticsearch_type => result
                                         }
                                       }
        puts 'Index created'
      rescue
        model.es_client.indices.put_mapping index: model.elasticsearch_index,
                                            type: model.elasticsearch_type,
                                            body: {
                                              model.elasticsearch_type => result
                                            }
        puts 'Mappings updated'
      end
    end
  end
end
