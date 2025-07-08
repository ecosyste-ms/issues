require 'rails_helper'

RSpec.describe GharchiveImporter do
  let(:github_host) { create(:host, name: 'GitHub') }
  let(:importer) { described_class.new(github_host) }
  
  describe '#import_hour' do
    let(:date) { Date.parse('2024-01-01') }
    let(:hour) { 12 }
    
    context 'when download is successful' do
      let(:compressed_data) { create_gzip_data(sample_events) }
      
      before do
        allow(importer).to receive(:download_file).and_return(compressed_data)
      end
      
      it 'processes issue events' do
        expect { importer.import_hour(date, hour) }.to change(Issue, :count).by(1)
        
        issue = Issue.last
        expect(issue.number).to eq(123)
        expect(issue.title).to eq('Test Issue')
        expect(issue.pull_request).to eq(false)
      end
      
      it 'processes pull request events' do
        expect { importer.import_hour(date, hour) }.to change(Issue, :count).by(1)
        
        pr = Issue.find_by(number: 456)
        expect(pr).to be_present
        expect(pr.pull_request).to eq(true)
        expect(pr.title).to eq('Test PR')
      end
      
      it 'creates repositories as needed' do
        expect { importer.import_hour(date, hour) }.to change(Repository, :count).by(1)
        
        repo = Repository.last
        expect(repo.full_name).to eq('test-owner/test-repo')
      end
    end
    
    context 'when download fails' do
      before do
        allow(importer).to receive(:download_file).and_return(nil)
      end
      
      it 'does not create any records' do
        expect { importer.import_hour(date, hour) }.not_to change(Issue, :count)
        expect { importer.import_hour(date, hour) }.not_to change(Repository, :count)
      end
    end
  end
  
  describe '#import_date_range' do
    let(:start_date) { Date.parse('2024-01-01') }
    let(:end_date) { Date.parse('2024-01-02') }
    
    it 'imports all hours for each day in range' do
      expect(importer).to receive(:import_hour).exactly(48).times
      importer.import_date_range(start_date, end_date)
    end
  end
  
  private
  
  def sample_events
    [
      {
        "type" => "IssuesEvent",
        "repo" => { "name" => "test-owner/test-repo" },
        "payload" => {
          "issue" => {
            "id" => 1,
            "number" => 123,
            "state" => "open",
            "title" => "Test Issue",
            "body" => "Test body",
            "locked" => false,
            "comments" => 5,
            "user" => { "login" => "testuser" },
            "author_association" => "CONTRIBUTOR",
            "html_url" => "https://github.com/test-owner/test-repo/issues/123",
            "created_at" => "2024-01-01T12:00:00Z",
            "updated_at" => "2024-01-01T12:00:00Z",
            "closed_at" => nil,
            "labels" => [{ "name" => "bug" }, { "name" => "help wanted" }],
            "assignees" => []
          }
        }
      },
      {
        "type" => "PullRequestEvent",
        "repo" => { "name" => "test-owner/test-repo" },
        "payload" => {
          "pull_request" => {
            "id" => 2,
            "number" => 456,
            "state" => "open",
            "title" => "Test PR",
            "body" => "Test PR body",
            "locked" => false,
            "comments" => 2,
            "user" => { "login" => "prauthor" },
            "author_association" => "MEMBER",
            "html_url" => "https://github.com/test-owner/test-repo/pull/456",
            "created_at" => "2024-01-01T12:30:00Z",
            "updated_at" => "2024-01-01T12:30:00Z",
            "closed_at" => nil,
            "merged_at" => nil,
            "labels" => [],
            "assignees" => [{ "login" => "reviewer1" }],
            "additions" => 10,
            "deletions" => 5,
            "changed_files" => 2,
            "commits" => 1,
            "review_comments" => 0,
            "mergeable_state" => "clean",
            "merge_commit_sha" => nil,
            "base" => { "ref" => "main" },
            "head" => { "ref" => "feature-branch" }
          }
        }
      },
      {
        "type" => "WatchEvent",
        "repo" => { "name" => "test-owner/test-repo" },
        "payload" => {}
      }
    ]
  end
  
  def create_gzip_data(events)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    events.each { |event| gz.puts(event.to_json) }
    gz.close
    io.string
  end
end