libdir = File.expand_path(File.dirname(__FILE__) + '/lib')
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'bundler/gem_tasks'
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  puts 'Did not load RSpec'
end

task default: :spec
