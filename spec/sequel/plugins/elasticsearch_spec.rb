# frozen-string-literal: true

require 'sequel'
require 'sequel/plugins/elasticsearch'
require 'sequel/plugins/elasticsearch/result'
require 'timecop'

# rubocop: disable Metrics/BlockLength
describe Sequel::Plugins::Elasticsearch do
  before(:all) do
    DB.create_table!(:documents) do
      primary_key :id
      String :title
      String :content, text: true
      Integer :views
      TrueClass :active
      DateTime :created_at
    end

    DB.create_table!(:complex_documents) do
      Integer :one
      Integer :two
      primary_key %i[one two]
      String :title
      String :content, text: true
    end
  end

  let(:model) do
    Class.new(Sequel::Model(:documents))
  end

  describe '.configure' do
    it 'defaults to the model table name for the index' do
      model.plugin :elasticsearch
      expect(model.send(:elasticsearch_index)).to eq :documents
    end

    it 'allows you to specify the index' do
      model.plugin :elasticsearch, index: :customIndex
      expect(model.elasticsearch_index).to eq :customIndex
    end

    it 'uses the specified index' do
      model.plugin :elasticsearch, index: :customIndex
      stub_request(:put, %r{http://localhost:9200/customIndex/_doc/\d+})
      doc = model.new.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/customIndex/_doc/#{doc.id}")
    end

    it 'defaults to `_doc` for the type' do
      model.plugin :elasticsearch
      expect(model.send(:elasticsearch_type)).to eq :_doc
    end

    it 'allows you to specify the type' do
      model.plugin :elasticsearch, type: :customType
      expect(model.send(:elasticsearch_type)).to eq :customType
    end

    it 'uses the specified type' do
      model.plugin :elasticsearch, type: :customType
      stub_request(:put, %r{http://localhost:9200/#{model.table_name}/customType/\d+})
      doc = model.new.save
      expect(WebMock).to have_requested(:put, "http://localhost:9200/#{model.table_name}/customType/#{doc.id}")
    end

    it 'allows you to pass down Elasticsearch client options' do
      model.plugin :elasticsearch, elasticsearch: { log: true }
      expect(model.new.es_client.transport.options).to include log: true
    end
  end

  describe 'ClassMethods' do
    describe '.es' do
      it 'does a basic query string search' do
        stub_request(:get, %r{http://localhost:9200/documents/_doc/_search.*})
        model.plugin :elasticsearch
        model.es('test')
        expect(WebMock).to have_requested(:get, 'http://localhost:9200/documents/_doc/_search?q=test')
      end

      it 'does a complex query search' do
        stub = stub_request(:get, 'http://localhost:9200/documents/_doc/_search')
               .with(body: '{"query":{"match":{"title":"test"}}}')
        model.plugin :elasticsearch
        model.es(query: { match: { title: 'test' } })
        expect(stub).to have_been_requested.once
      end

      it 'handles not found exceptions' do
        stub_request(:get, %r{http://localhost:9200/documents/_doc/_search.*})
          .to_return(status: 404)
        model.plugin :elasticsearch
        expect { model.es('test') }.not_to raise_error
      end

      it 'handles connection failed exceptions' do
        stub_request(:get, %r{http://localhost:9200/documents/_doc/_search.*})
        allow(Faraday::Connection).to receive(:get).and_raise(Faraday::ConnectionFailed)
        model.plugin :elasticsearch
        expect { model.es('test') }.not_to raise_error
      end

      it 'returns an enumerable' do
        stub_request(:get, %r{http://localhost:9200/documents/_doc/_search.*})
        model.plugin :elasticsearch
        expect(model.es('test')).to be_a Enumerable
      end

      it 'handles scroll requests' do
        stub = stub_request(:get, 'http://localhost:9200/documents/_doc/_search?q=test&scroll=1m')
        model.plugin :elasticsearch
        model.es('test', scroll: '1m')
        expect(stub).to have_been_requested.once
      end

      it 'handles scroll results'
    end

    describe '.es!' do
      it 'does not handle exceptions' do
        stub_request(:get, %r{http://localhost:9200/documents/_doc/_search.*})
          .to_return(status: 500)
        model.plugin :elasticsearch
        expect { model.es!('test') }.to raise_error Elasticsearch::Transport::Transport::Error
      end
    end

    describe '.scroll!' do
      it 'accepts a scroll_id' do
        stub = stub_request(:get, 'http://localhost:9200/_search/scroll?scroll%5Bscroll%5D=1m&scroll_id=somescrollid')
               .to_return(status: 200)
        model.plugin :elasticsearch
        model.scroll!('somescrollid', scroll: '1m')
        expect(stub).to have_been_requested.once
      end

      it 'accepts a Result' do
        result = Sequel::Plugins::Elasticsearch::Result.new('_scroll_id' => 'somescrollid')
        allow(result).to receive(:scroll_id).and_return('somescrollid')
        stub = stub_request(:get, 'http://localhost:9200/_search/scroll?scroll%5Bscroll%5D=1m&scroll_id=somescrollid')
               .to_return(status: 200)
        model.plugin :elasticsearch
        model.scroll!(result, scroll: '1m')
        expect(stub).to have_been_requested.once
      end

      it 'does not handle exceptions' do
        stub_request(:get, 'http://localhost:9200/_search/scroll?scroll=1m&scroll_id=somescrollid')
          .to_return(status: 500)
        model.plugin :elasticsearch
        expect { model.scroll!('somescrollid', '1m') }.to raise_error Elasticsearch::Transport::Transport::Error
      end
    end

    describe '.timestamped_index' do
      it 'returns the index appended with a timestamp' do
        model.plugin :elasticsearch
        Timecop.freeze(Time.local(2019, 12, 4, 21, 26, 12)) do
          expect(model.timestamped_index).to eq :'documents-20191204.212612'
        end
      end
    end
  end

  describe 'InstanceMethods' do
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

    describe '#es_client' do
      it 'returns an Elasticsearch Transport Client' do
        expect(simple_doc.new.send(:es_client)).to be_a Elasticsearch::Transport::Client
      end
    end

    describe '#document_id' do
      it 'returns the value of the primary key for simple primary keys' do
        stub_request(:put, %r{http://localhost:9200/documents/_doc/\d+})
        doc = simple_doc.new.save
        expect(doc.send(:document_id)).to eq doc.id
      end

      it 'returns the value of the primary key for composite primary keys' do
        complex_doc.insert(one: 1, two: 2)
        doc = complex_doc.first
        expect(doc.send(:document_id)).to eq "#{doc.one}_#{doc.two}"
      end
    end

    describe '#as_indexed_json' do
      let(:doc) do
        simple_doc.new(
          title: 'title',
          content: 'content',
          views: 4,
          active: true,
          created_at: Time.parse('2018-02-07T22:18:42+02:00')
        )
      end

      it 'correctly formats dates and other types' do
        expect(doc.as_indexed_json).to include(
          title: 'title', content: 'content', views: 4, active: true, created_at: '2018-02-07T22:18:42+02:00'
        )
      end

      it 'can be extended' do
        doc = simple_doc.new
        def doc.as_indexed_json
          { test: 'this' }
        end
        expect(doc.as_indexed_json).to include(test: 'this')
      end
    end

    describe '#document_path' do
      it 'returns the document index, type and id for documents' do
        stub_request(:put, %r{http://localhost:9200/documents/_doc/\d+})
        doc = simple_doc.new.save
        expect(doc.document_path).to include index: simple_doc.table_name
        expect(doc.document_path).to include type: :_doc
        expect(doc.document_path).to include id: doc.id
      end
    end

    describe '#save' do
      it 'indexes the document using the document path and model values' do
        stub_request(:put, %r{http://localhost:9200/documents/_doc/\d+})
        doc = simple_doc.new.save
        expect(WebMock)
          .to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/_doc/#{doc.id}")
      end
    end

    describe '#update' do
      let(:doc) do
        doc = simple_doc.new.save
        doc.title = 'updated'
        doc.save
        doc
      end

      it 'indexes the document using the document path and model values' do
        stub_request(:put, %r{http://localhost:9200/documents/_doc/\d+})
        expect(WebMock)
          .to have_requested(:put, "http://localhost:9200/#{simple_doc.table_name}/_doc/#{doc.id}")
          .times(2)
      end
    end

    describe '#destroy' do
      let(:id) do
        doc = simple_doc.new.save
        id = doc.pk
        doc.destroy
        id
      end

      it 'destroys the document using the document path' do
        stub_request(:put, %r{http://localhost:9200/documents/_doc/\d+})
        stub_request(:delete, %r{http://localhost:9200/documents/_doc/\d+})
        expect(WebMock)
          .to have_requested(:delete, "http://localhost:9200/#{simple_doc.table_name}/_doc/#{id}")
      end
    end
  end
end
# rubocop: enable Metrics/BlockLength
