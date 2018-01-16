require 'sequel'
require 'sequel/plugins/elasticsearch'

describe Sequel::Plugins::Elasticsearch do
  context '.apply' do
  end

  context '.configure' do
  end
end

describe Sequel::Plugins::Elasticsearch::InstanceMethods do
  before(:all) do
    DB.create_table!(:documents) do
      primary_key :id
      String :title
      String :content, text: true
    end

    DB.create_table!(:complex_documents) do
      Integer :one
      Integer :two
      primary_key [:one, :two]
      String :title
      String :content, text: true
    end
  end

  let(:simple_doc) do
    @subj ||= begin
      subj = Class.new(Sequel::Model(:documents))
      subj.plugin :elasticsearch
      subj
    end
  end

  let(:complex_doc) do
    @subj ||= begin
      subj = Class.new(Sequel::Model(:complex_documents))
      subj.plugin :elasticsearch
      subj
    end
  end

  context '#es_client' do
    it 'returns an Elasticsearch Transport Client' do
      expect(simple_doc.new.send(:es_client)).to be_a Elasticsearch::Transport::Client
    end
  end

  context '#document_id' do
    it 'returns the value of the primary key for simple primary keys' do
      stub_request(:put, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      doc = simple_doc.new.save
      expect(doc.send(:document_id)).to eq doc.id
    end

    it 'returns the value of the primary key for composite primary keys' do
      complex_doc.insert(one: 1, two: 2)
      doc = complex_doc.first
      expect(doc.send(:document_id)).to eq "#{doc.one}_#{doc.two}"
    end
  end

  context '#document_path' do
    it 'returns the document index, type and id for documents' do
      stub_request(:put, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      doc = simple_doc.new.save
      expect(doc.send(:document_path)).to include index: simple_doc.table_name
      expect(doc.send(:document_path)).to include type: 'sync'
      expect(doc.send(:document_path)).to include id: doc.id
    end
  end

  context '#save' do
    it 'indexes the document using the document path and model values' do
      stub_request(:put, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      doc = simple_doc.new.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/sync/#{doc.id}")
    end
  end

  context '#update' do
    it 'indexes the document using the document path and model values' do
      stub_request(:put, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      doc = simple_doc.new.save
      doc.title = 'updated'
      doc.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/sync/#{doc.id}").times(2)
    end
  end

  context '#destroy' do
    it 'destroys the document using the document path' do
      stub_request(:put, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      stub_request(:delete, /http:\/\/localhost:9200\/documents\/sync\/\d+/)
      doc = simple_doc.new.save
      id = doc.pk
      doc.destroy
      expect(WebMock).to have_requested(:delete, "http://localhost:9200/#{simple_doc.table_name}/sync/#{id}")
    end
  end
end
