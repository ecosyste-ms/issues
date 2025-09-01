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
end