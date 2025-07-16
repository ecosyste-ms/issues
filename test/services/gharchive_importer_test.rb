require 'test_helper'

class GharchiveImporterTest < ActiveSupport::TestCase
  def setup
    @host = hosts(:github)
    @importer = GharchiveImporter.new(@host)
  end

  test "bulk_upsert_issues deduplicates issues with same uuid" do
    repository = repositories(:rails)
    
    # Create duplicate issue data with same uuid but different titles
    duplicate_issues_data = [
      {
        uuid: '12345',
        host_id: @host.id,
        repository_id: repository.id,
        number: 1,
        state: 'open',
        title: 'First title',
        locked: false,
        comments_count: 0,
        user: 'user1',
        author_association: 'NONE',
        pull_request: false,
        created_at: Time.current,
        updated_at: Time.current,
        closed_at: nil,
        merged_at: nil,
        labels: [],
        assignees: [],
        time_to_close: nil
      },
      {
        uuid: '12345', # Same uuid - should be deduplicated
        host_id: @host.id,
        repository_id: repository.id,
        number: 1,
        state: 'open',
        title: 'Updated title', # This should be kept (last occurrence)
        locked: false,
        comments_count: 1,
        user: 'user1',
        author_association: 'NONE',
        pull_request: false,
        created_at: Time.current,
        updated_at: Time.current,
        closed_at: nil,
        merged_at: nil,
        labels: [],
        assignees: [],
        time_to_close: nil
      }
    ]
    
    assert_no_difference 'Issue.count' do
      @importer.send(:bulk_upsert_issues, duplicate_issues_data)
    end
    
    # Should create only one issue with the latest data
    assert_difference 'Issue.count', 1 do
      @importer.send(:bulk_upsert_issues, duplicate_issues_data)
    end
    
    created_issue = Issue.find_by(uuid: '12345')
    assert_equal 'Updated title', created_issue.title
    assert_equal 1, created_issue.comments_count
  end
end