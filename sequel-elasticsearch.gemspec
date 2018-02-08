
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sequel/plugins/elasticsearch/version'

Gem::Specification.new do |spec|
  spec.name          = 'sequel-elasticsearch'
  spec.version       = Sequel::Elasticsearch::VERSION
  spec.authors       = ['Jurgens du Toit']
  spec.email         = ['jrgns@jadeit.co.za']

  spec.summary       = 'A plugin for the Sequel gem to sync data to Elasticsearch.'
  spec.description   = 'A plugin for the Sequel gem to sync data to Elasticsearch.'
  spec.homepage      = 'https://github.com/jrgns/sequel-elasticsearch'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'elasticsearch', '>= 1.0'
  spec.add_dependency 'sequel', '>= 4.0'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 0.52'
  spec.add_development_dependency 'simplecov', '~> 0.15'
  spec.add_development_dependency 'webmock', '~> 3.2'
end
