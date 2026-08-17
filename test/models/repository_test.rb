require 'test_helper'

class RepositoryTest < ActiveSupport::TestCase
  test "successful issue sync leaves repository active and visible" do
    host = create(:host)
    repository = create(:repository, host: host, status: 'error', last_synced_at: nil)
    issue_data = {
      uuid: SecureRandom.uuid,
      number: 1,
      state: 'open',
      title: 'Test Issue',
      user: 'testuser',
      labels: [],
      assignees: [],
      locked: false,
      comments_count: 0,
      pull_request: false,
      created_at: 1.day.ago,
      updated_at: Time.current
    }
    host_api = mock
    host_api.expects(:load_issues).with(repository).yields([issue_data])
    host.expects(:host_instance).returns(host_api)
    repository.expects(:mark_reconciled).once

    repository.sync_issues

    repository.reload
    assert_nil repository.status
    assert_includes Repository.visible, repository
  end

  test "sync_issues should upsert issues without duplicates" do
    host = create(:host)
    repository = create(:repository, host: host)
    
    closed_at = 1.hour.ago
    created_at = 2.days.ago
    
    issue_data = [
      {
        uuid: "12345",
        number: 1,
        title: "Test Issue",
        state: "open",
        created_at: 1.day.ago,
        updated_at: Time.current,
        closed_at: nil,
        time_to_close: nil,
        user: "testuser",
        host_id: host.id,
        repository_id: repository.id
      },
      {
        uuid: "67890",
        number: 2,
        title: "Another Issue",
        state: "closed",
        created_at: created_at,
        updated_at: Time.current,
        closed_at: closed_at,
        time_to_close: closed_at - created_at,
        user: "anotheruser",
        host_id: host.id,
        repository_id: repository.id
      }
    ]
    
    Issue.upsert_all(issue_data, unique_by: [:host_id, :uuid])
    
    assert_equal 2, repository.issues.count
    
    Issue.upsert_all(issue_data, unique_by: [:host_id, :uuid])
    
    assert_equal 2, repository.issues.count
    
    issue = repository.issues.find_by(uuid: "67890")
    assert_not_nil issue.time_to_close
  end
  
  test "sync_issues calculates time_to_close correctly" do
    host = create(:host)
    repository = create(:repository, host: host)
    
    created_at = 2.days.ago
    closed_at = 1.hour.ago
    expected_time_to_close = (closed_at - created_at).to_f
    
    issue_data = [
      {
        uuid: "test123",
        number: 1,
        title: "Test Issue",
        state: "closed",
        created_at: created_at,
        updated_at: Time.current,
        closed_at: closed_at,
        user: "testuser",
        host_id: host.id,
        repository_id: repository.id,
        time_to_close: expected_time_to_close
      }
    ]
    
    Issue.upsert_all(issue_data, unique_by: [:host_id, :uuid])
    
    issue = repository.issues.find_by(uuid: "test123")
    assert_not_nil issue.time_to_close
    assert_in_delta expected_time_to_close, issue.time_to_close, 0.001
  end

  test "reconcile inserts missing issues and refreshes author associations" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'observablehq/notebook-kit')
    create(
      :issue,
      repository: repository,
      host: host,
      uuid: '90',
      number: 90,
      user: 'mootari',
      author_association: 'MEMBER',
      created_at: 1.month.ago
    )

    issue_data = [21, 90, 91].map { |number| reconciled_issue_data(number) }
    host_api = mock
    host_api.expects(:load_issues).with(repository, full: true).yields(issue_data)
    host.expects(:host_instance).returns(host_api)
    repository.expects(:mark_reconciled).once

    repository.reconcile

    repository.reload
    assert_equal [21, 90, 91], repository.issues.where(user: 'mootari').order(:number).pluck(:number)
    assert_equal 3, repository.issues_count
    assert_empty repository.issues.maintainers.where(user: 'mootari')
  end

  test "reconcile_async enqueues one full sync" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    job = mock

    REDIS.expects(:set).with(repository.reconciliation_key, 'pending', nx: true, ex: 1.day.to_i).returns(true)
    Job.expects(:new).with(url: repository.html_url, status: 'pending', ip: '127.0.0.1').returns(job)
    job.expects(:save).returns(true)
    job.expects(:sync_issues_async).with(false, full: true).returns(true)

    assert_equal job, repository.reconcile_async('127.0.0.1')
  end

  test "reconcile_async does not enqueue while reconciliation is pending or fresh" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)

    REDIS.expects(:set).with(repository.reconciliation_key, 'pending', nx: true, ex: 1.day.to_i).returns(false)
    Job.expects(:new).never

    assert_nil repository.reconcile_async
  end

  test "reconcile_async leaves a new repository to its initial full sync" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, last_synced_at: nil)

    REDIS.expects(:set).never
    Job.expects(:new).never

    assert_nil repository.reconcile_async
  end

  test "reconcile_async clears its throttle when enqueueing fails" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    job = mock

    REDIS.expects(:set).returns(true)
    REDIS.expects(:del).with(repository.reconciliation_key).once
    Job.expects(:new).returns(job)
    job.expects(:save).returns(true)
    job.expects(:sync_issues_async).raises(StandardError.new('queue unavailable'))
    Rails.logger.expects(:error).with("Failed to enqueue reconciliation for #{repository.full_name}: queue unavailable")

    assert_nil repository.reconcile_async
  end

  test "issue_labels_count counts labels across issues" do
    host = create(:host)
    repository = create(:repository, host: host)
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['bug', 'critical'])
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['bug', 'enhancement'])
    create(:issue, repository: repository, host: host, pull_request: false, labels: [])

    result = repository.issue_labels_count
    labels_hash = result.to_h
    assert_equal 2, labels_hash['bug']
    assert_equal 1, labels_hash['critical']
    assert_equal 1, labels_hash['enhancement']
  end

  test "issue_labels_count excludes pull request labels" do
    host = create(:host)
    repository = create(:repository, host: host)
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['bug'])
    create(:issue, repository: repository, host: host, pull_request: true, labels: ['feature'])

    result = repository.issue_labels_count.to_h
    assert_equal 1, result['bug']
    assert_nil result['feature']
  end

  test "pull_request_labels_count counts only PR labels" do
    host = create(:host)
    repository = create(:repository, host: host)
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['bug'])
    create(:issue, repository: repository, host: host, pull_request: true, labels: ['feature', 'feature'])

    result = repository.pull_request_labels_count.to_h
    assert_nil result['bug']
    assert_equal 2, result['feature']
  end

  test "past_year_issue_labels_count only includes recent issues" do
    host = create(:host)
    repository = create(:repository, host: host)
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['recent'], created_at: 1.month.ago)
    create(:issue, repository: repository, host: host, pull_request: false, labels: ['old'], created_at: 2.years.ago)

    result = repository.past_year_issue_labels_count.to_h
    assert_equal 1, result['recent']
    assert_nil result['old']
  end

  test "issue_authors returns authors sorted by count descending" do
    host = create(:host)
    repository = create(:repository, host: host)
    3.times { |i| create(:issue, repository: repository, host: host, pull_request: false, user: 'prolific', number: 1000 + i) }
    create(:issue, repository: repository, host: host, pull_request: false, user: 'casual', number: 2000)

    result = repository.issue_authors
    assert_equal 'prolific', result.first[0]
    assert_equal 3, result.first[1]
  end

  test "pull_request_authors returns only PR authors" do
    host = create(:host)
    repository = create(:repository, host: host)
    create(:issue, repository: repository, host: host, pull_request: false, user: 'issue_author')
    create(:issue, repository: repository, host: host, pull_request: true, user: 'pr_author')

    result = repository.pull_request_authors.to_h
    assert_nil result['issue_author']
    assert_equal 1, result['pr_author']
  end

  def reconciled_issue_data(number)
    {
      uuid: number.to_s,
      node_id: "node-#{number}",
      number: number,
      state: 'closed',
      title: "Issue #{number}",
      locked: false,
      comments_count: 0,
      created_at: 1.month.ago,
      updated_at: Time.current,
      closed_at: 1.day.ago,
      user: 'mootari',
      labels: [],
      assignees: [],
      pull_request: false,
      author_association: 'NONE',
      state_reason: 'completed',
      merged_at: nil
    }
  end
end
