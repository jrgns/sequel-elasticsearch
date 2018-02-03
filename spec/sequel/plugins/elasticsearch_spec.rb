require 'sequel'
require 'sequel/plugins/elasticsearch'

describe Sequel::Plugins::Elasticsearch do
  before(:all) do
    DB.create_table!(:documents) do
      primary_key :id
      String :title
      String :content, text: true
    end

    DB.create_table!(:complex_documents) do
      Integer :one
      Integer :two
      primary_key %i[one two]
      String :title
      String :content, text: true
    end
  end

  let(:subject) do
    Class.new(Sequel::Model(:documents))
  end

  context '.configure' do
    it 'defaults to the model table name for the index' do
      subject.plugin :elasticsearch
      expect(subject.send(:elasticsearch_index)).to eq :documents
    end

    it 'allows you to specify the index' do
      subject.plugin :elasticsearch, index: :customIndex
      expect(subject.elasticsearch_index).to eq :customIndex
    end

    it 'uses the specified index' do
      subject.plugin :elasticsearch, index: :customIndex
      stub_request(:put, %r{http://localhost:9200/customIndex/sync/\d+})
      doc = subject.new.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/customIndex/sync/#{doc.id}")
    end

    it 'defaults to `sync` for the type' do
      subject.plugin :elasticsearch
      expect(subject.send(:elasticsearch_type)).to eq :sync
    end

    it 'allows you to specify the type' do
      subject.plugin :elasticsearch, type: :customType
      expect(subject.send(:elasticsearch_type)).to eq :customType
    end

    it 'uses the specified type' do
      subject.plugin :elasticsearch, type: :customType
      stub_request(:put, %r{http://localhost:9200/#{subject.table_name}/customType/\d+})
      doc = subject.new.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/#{subject.table_name}/customType/#{doc.id}")
    end

    it 'allows you to pass down Elasticsearch client options' do
      subject.plugin :elasticsearch, elasticsearch: { log: true }
      expect(subject.new.es_client.transport.options).to include log: true
    end
  end

  context 'InstanceMethods' do
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

    context '#es' do
      it 'does a basic query string search' do
        stub_request(:get, %r{http://localhost:9200/documents/sync/_search.*})
        subject.plugin :elasticsearch
        subject.new.es('test')
        expect(WebMock).to have_requested(:get, 'http://localhost:9200/documents/sync/_search?q=test')
      end

      it 'does a complex query search' do
        stub = stub_request(:get, 'http://localhost:9200/documents/sync/_search')
               .with(body: '{"query":{"match":{"title":"test"}}}')
        subject.plugin :elasticsearch
        subject.new.es(query: { match: { title: 'test' } })
        expect(stub).to have_been_requested.once
      end
    end

    context '#es_client' do
      it 'returns an Elasticsearch Transport Client' do
        expect(simple_doc.new.send(:es_client)).to be_a Elasticsearch::Transport::Client
      end
    end

    context '#document_id' do
      it 'returns the value of the primary key for simple primary keys' do
        stub_request(:put, %r{http://localhost:9200/documents/sync/\d+})
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
        stub_request(:put, %r{http://localhost:9200/documents/sync/\d+})
        doc = simple_doc.new.save
        expect(doc.send(:document_path)).to include index: simple_doc.table_name
        expect(doc.send(:document_path)).to include type: :sync
        expect(doc.send(:document_path)).to include id: doc.id
      end
    end

    context '#save' do
      it 'indexes the document using the document path and model values' do
        stub_request(:put, %r{http://localhost:9200/documents/sync/\d+})
        doc = simple_doc.new.save
        expect(WebMock)
          .to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/sync/#{doc.id}")
      end
    end

    context '#update' do
      it 'indexes the document using the document path and model values' do
        stub_request(:put, %r{http://localhost:9200/documents/sync/\d+})
        doc = simple_doc.new.save
        doc.title = 'updated'
        doc.save
        expect(WebMock)
          .to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/sync/#{doc.id}")
          .times(2)
      end
    end

    context '#destroy' do
      it 'destroys the document using the document path' do
        stub_request(:put, %r{http://localhost:9200/documents/sync/\d+})
        stub_request(:delete, %r{http://localhost:9200/documents/sync/\d+})
        doc = simple_doc.new.save
        id = doc.pk
        doc.destroy
        expect(WebMock)
          .to have_requested(:delete, "http://localhost:9200/#{simple_doc.table_name}/sync/#{id}")
      end
    end
  end
end
