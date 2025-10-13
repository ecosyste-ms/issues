require 'test_helper'

class GharchiveImporterTest < ActiveSupport::TestCase
  def setup
    @host = create(:host, :github)
    @importer = GharchiveImporter.new(@host)
  end

  test "import_hour processes issue and pull request events" do
    date = Date.parse('2024-01-01')
    hour = 12
    
    compressed_data = create_gzip_data(sample_events)
    @importer.stubs(:download_file).returns(compressed_data)
    
    assert_difference 'Issue.count', 2 do
      assert_difference 'Repository.count', 1 do
        @importer.import_hour(date, hour)
      end
    end
    
    issue = Issue.find_by(number: 123)
    assert_equal 'Test Issue', issue.title
    assert_equal false, issue.pull_request
    
    pr = Issue.find_by(number: 456)
    assert_equal 'Test PR', pr.title
    assert_equal true, pr.pull_request
    
    repo = Repository.find_by(full_name: 'test-owner/test-repo')
    assert_equal 'test-owner', repo.owner
  end

  test "import_hour skips already imported hours" do
    date = Date.parse('2024-01-01')
    hour = 12
    
    Import.create!(
      filename: Import.filename_for(date, hour),
      imported_at: Time.current,
      success: true
    )
    
    assert_no_difference 'Issue.count' do
      result = @importer.import_hour(date, hour)
      assert result
    end
  end

  test "import_hour handles download failures" do
    date = Date.parse('2024-01-01')
    hour = 12
    
    @importer.stubs(:download_file).returns(nil)
    
    assert_no_difference 'Issue.count' do
      result = @importer.import_hour(date, hour)
      assert_not result
    end
  end

  test "import_date_range calls import_hour for each hour" do
    start_date = Date.parse('2024-01-01')
    end_date = Date.parse('2024-01-02')
    
    expected_calls = 48 # 24 hours * 2 days
    @importer.expects(:import_hour).times(expected_calls)
    
    @importer.import_date_range(start_date, end_date)
  end

  test "batch_upsert_repositories creates repositories in batch" do
    repo_names = ['owner1/repo1', 'owner2/repo2', 'owner1/repo3']
    
    assert_difference 'Repository.count', 3 do
      result = @importer.send(:batch_upsert_repositories, repo_names)
      
      assert_equal 3, result.size
      assert result.all? { |_name, repo| repo.is_a?(Repository) }
      assert_equal repo_names.sort, result.keys.sort
    end
  end

  test "batch_upsert_repositories handles existing repositories" do
    existing_repo = Repository.create!(
      host: @host,
      full_name: 'owner1/repo1',
      owner: 'owner1'
    )
    
    repo_names = ['owner1/repo1', 'owner2/repo2']
    
    assert_difference 'Repository.count', 1 do
      result = @importer.send(:batch_upsert_repositories, repo_names)
      
      assert_equal 2, result.size
      assert_equal existing_repo.id, result['owner1/repo1'].id
    end
  end

  test "batch_upsert_repositories handles case-insensitive matching" do
    # Create a repository with lowercase name
    existing_repo = Repository.create!(
      host: @host,
      full_name: 'shahadatanik/bwt-frontend',
      owner: 'shahadatanik'
    )
    
    # Try to upsert with different case
    repo_names = ['ShahadatAnik/BWT-FRONTEND', 'LibreCodeCoop/site']
    
    assert_difference 'Repository.count', 1 do
      result = @importer.send(:batch_upsert_repositories, repo_names)
      
      # Should find the existing repo despite case difference
      assert_equal 2, result.size
      assert result.key?('ShahadatAnik/BWT-FRONTEND'), "Should have key with original case"
      assert_equal existing_repo.id, result['ShahadatAnik/BWT-FRONTEND'].id
      assert_equal 'shahadatanik/bwt-frontend', result['ShahadatAnik/BWT-FRONTEND'].full_name
    end
  end

  test "batch_upsert_repositories handles invalid repository names" do
    invalid_names = ['invalid', '', 'owner1/repo1']
    
    assert_difference 'Repository.count', 1 do
      result = @importer.send(:batch_upsert_repositories, invalid_names)
      
      assert_equal 1, result.size
      assert result.key?('owner1/repo1')
    end
  end

  test "bulk_upsert_issues creates issues in batch" do
    repository = create(:repository, :rails, host: @host)
    
    issues_data = [
      build_issue_data(1, repository, 'Issue 1', false),
      build_issue_data(2, repository, 'PR 1', true)
    ]
    
    assert_difference 'Issue.count', 2 do
      @importer.send(:bulk_upsert_issues, issues_data)
    end
    
    stats = @importer.import_stats
    assert_equal 1, stats[:issues_count]
    assert_equal 1, stats[:pull_requests_count]
    assert_equal 2, stats[:created_count]
    assert_equal 0, stats[:updated_count]
  end

  test "bulk_upsert_issues deduplicates issues with same uuid" do
    repository = create(:repository, :rails, host: @host)
    
    duplicate_issues_data = [
      build_issue_data(12345, repository, 'First title', false),
      build_issue_data(12345, repository, 'Updated title', false, comments_count: 1)
    ]
    
    assert_difference 'Issue.count', 1 do
      @importer.send(:bulk_upsert_issues, duplicate_issues_data)
    end
    
    created_issue = Issue.find_by(uuid: 12345)
    assert_equal 'Updated title', created_issue.title
    assert_equal 1, created_issue.comments_count
  end

  test "bulk_upsert_issues updates existing issues" do
    repository = create(:repository, :rails, host: @host)
    existing_issue = Issue.create!(
      uuid: 123,
      host: @host,
      repository: repository,
      number: 1,
      title: 'Old Title',
      state: 'open',
      pull_request: false,
      user: 'user1',
      created_at: Time.current,
      updated_at: Time.current
    )
    
    updated_data = [build_issue_data(123, repository, 'Updated Title', false, 
                                   state: 'closed', comments_count: 5)]
    
    assert_no_difference 'Issue.count' do
      @importer.send(:bulk_upsert_issues, updated_data)
    end
    
    existing_issue.reload
    assert_equal 'Updated Title', existing_issue.title
    assert_equal 'closed', existing_issue.state
    assert_equal 5, existing_issue.comments_count
    
    stats = @importer.import_stats
    assert_equal 0, stats[:created_count]
    assert_equal 1, stats[:updated_count]
  end

  test "bulk_upsert_issues processes large batches" do
    repository = create(:repository, :rails, host: @host)
    
    large_data = 1500.times.map do |i|
      build_issue_data(i, repository, "Issue #{i}", false)
    end
    
    assert_difference 'Issue.count', 1500 do
      @importer.send(:bulk_upsert_issues, large_data)
    end
    
    stats = @importer.import_stats
    assert_equal 1500, stats[:issues_count]
    assert_equal 0, stats[:pull_requests_count]
    assert_equal 1500, stats[:created_count]
  end

  test "bulk_upsert_issues handles empty data" do
    assert_no_difference 'Issue.count' do
      @importer.send(:bulk_upsert_issues, [])
    end
  end

  test "process_events uses batch operations" do
    events = sample_events
    
    repository = create(:repository, :rails, host: @host)
    @importer.expects(:batch_upsert_repositories).with(['test-owner/test-repo']).returns({
      'test-owner/test-repo' => repository
    })
    
    @importer.expects(:bulk_upsert_issues).with do |issues_data|
      issues_data.size == 2 &&
      issues_data.any? { |issue| issue[:pull_request] == false } &&
      issues_data.any? { |issue| issue[:pull_request] == true }
    end
    
    @importer.send(:process_events, events)
  end

  test "find_or_create_repository creates repository when not exists" do
    repo_name = 'newowner/newrepo'
    
    assert_difference 'Repository.count', 1 do
      result = @importer.send(:find_or_create_repository, repo_name)
      
      assert_equal repo_name, result.full_name
      assert_equal 'newowner', result.owner
      assert_equal @host.id, result.host_id
    end
  end

  test "find_or_create_repository returns existing repository" do
    existing_repo = create(:repository, :rails, host: @host)
    
    assert_no_difference 'Repository.count' do
      result = @importer.send(:find_or_create_repository, existing_repo.full_name)
      
      assert_equal existing_repo.id, result.id
    end
  end

  test "find_or_create_repository handles invalid names" do
    assert_nil @importer.send(:find_or_create_repository, 'invalid')
    assert_nil @importer.send(:find_or_create_repository, '')
    assert_nil @importer.send(:find_or_create_repository, nil)
  end

  test "map_issue_event extracts correct data" do
    event = {
      'type' => 'IssuesEvent',
      'payload' => {
        'issue' => {
          'id' => 123,
          'number' => 456,
          'state' => 'open',
          'title' => 'Test Issue',
          'locked' => false,
          'comments' => 5,
          'user' => { 'login' => 'testuser' },
          'author_association' => 'CONTRIBUTOR',
          'created_at' => '2024-01-01T12:00:00Z',
          'updated_at' => '2024-01-01T12:00:00Z',
          'closed_at' => nil,
          'labels' => [{ 'name' => 'bug' }],
          'assignees' => [{ 'login' => 'assignee1' }]
        }
      }
    }
    
    repository = create(:repository, :rails, host: @host)
    result = @importer.send(:map_issue_event, event, repository)
    
    assert_equal 123, result[:uuid]
    assert_equal 456, result[:number]
    assert_equal 'open', result[:state]
    assert_equal 'Test Issue', result[:title]
    assert_equal false, result[:pull_request]
    assert_equal 5, result[:comments_count]
    assert_equal 'testuser', result[:user]
    assert_equal ['bug'], result[:labels]
    assert_equal ['assignee1'], result[:assignees]
  end

  test "map_pull_request_event extracts correct data from old format" do
    event = {
      'type' => 'PullRequestEvent',
      'payload' => {
        'pull_request' => {
          'id' => 789,
          'number' => 101,
          'state' => 'open',
          'title' => 'Test PR',
          'locked' => false,
          'comments' => 2,
          'user' => { 'login' => 'prauthor' },
          'author_association' => 'MEMBER',
          'created_at' => '2024-01-01T12:30:00Z',
          'updated_at' => '2024-01-01T12:30:00Z',
          'closed_at' => nil,
          'merged_at' => nil,
          'labels' => [],
          'assignees' => []
        }
      }
    }

    repository = create(:repository, :rails, host: @host)
    result = @importer.send(:map_pull_request_event, event, repository)

    assert_equal 789, result[:uuid]
    assert_equal 101, result[:number]
    assert_equal 'open', result[:state]
    assert_equal 'Test PR', result[:title]
    assert_equal true, result[:pull_request]
    assert_equal 2, result[:comments_count]
    assert_equal 'prauthor', result[:user]
    assert_equal [], result[:labels]
    assert_equal [], result[:assignees]
  end

  test "map_pull_request_event handles new minimal format with default values" do
    event = {
      'type' => 'PullRequestEvent',
      'payload' => {
        'pull_request' => {
          'id' => 2907834030,
          'number' => 5,
          'url' => 'https://api.github.com/repos/test-owner/test-repo/pulls/5',
          'base' => { 'ref' => 'main' },
          'head' => { 'ref' => 'feature' }
        }
      }
    }

    repository = create(:repository, :rails, host: @host, full_name: 'test-owner/test-repo')

    result = @importer.send(:map_pull_request_event, event, repository)

    assert_not_nil result
    assert_equal 2907834030, result[:uuid]
    assert_equal 5, result[:number]
    assert_equal 'open', result[:state] # Default value
    assert_equal 'PR #5', result[:title] # Default title
    assert_equal true, result[:pull_request]
    assert_equal 0, result[:comments_count]
    assert_nil result[:user]
    assert_equal [], result[:labels]
  end

  private

  def build_issue_data(uuid, repository, title, pull_request, **options)
    {
      uuid: uuid,
      host_id: @host.id,
      repository_id: repository.id,
      number: options[:number] || 1,
      state: options[:state] || 'open',
      title: title,
      locked: false,
      comments_count: options[:comments_count] || 0,
      user: options[:user] || 'user1',
      author_association: options[:author_association] || 'CONTRIBUTOR',
      pull_request: pull_request,
      created_at: options[:created_at] || Time.current,
      updated_at: options[:updated_at] || Time.current,
      closed_at: options[:closed_at],
      merged_at: options[:merged_at],
      labels: options[:labels] || [],
      assignees: options[:assignees] || [],
      time_to_close: options[:time_to_close]
    }
  end

  def sample_events
    [
      {
        'type' => 'IssuesEvent',
        'repo' => { 'name' => 'test-owner/test-repo' },
        'payload' => {
          'issue' => {
            'id' => 1,
            'number' => 123,
            'state' => 'open',
            'title' => 'Test Issue',
            'locked' => false,
            'comments' => 5,
            'user' => { 'login' => 'testuser' },
            'author_association' => 'CONTRIBUTOR',
            'created_at' => '2024-01-01T12:00:00Z',
            'updated_at' => '2024-01-01T12:00:00Z',
            'closed_at' => nil,
            'labels' => [{ 'name' => 'bug' }],
            'assignees' => []
          }
        }
      },
      {
        'type' => 'PullRequestEvent',
        'repo' => { 'name' => 'test-owner/test-repo' },
        'payload' => {
          'pull_request' => {
            'id' => 2,
            'number' => 456,
            'state' => 'open',
            'title' => 'Test PR',
            'locked' => false,
            'comments' => 2,
            'user' => { 'login' => 'prauthor' },
            'author_association' => 'MEMBER',
            'created_at' => '2024-01-01T12:30:00Z',
            'updated_at' => '2024-01-01T12:30:00Z',
            'closed_at' => nil,
            'merged_at' => nil,
            'labels' => [],
            'assignees' => []
          }
        }
      },
      {
        'type' => 'WatchEvent',
        'repo' => { 'name' => 'test-owner/test-repo' },
        'payload' => {}
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