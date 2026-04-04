require 'test_helper'

class RepositoryTest < ActiveSupport::TestCase
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
end