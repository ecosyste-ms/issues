require "test_helper"

class IssueTest < ActiveSupport::TestCase
  test "delete_gharchive_duplicates removes archive pull request rows the issues API has replaced" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    duplicate = create(:issue, repository: repository, number: 1, pull_request: true, node_id: nil)
    create(:issue, repository: repository, number: 1, pull_request: true, node_id: 'PR_1')
    archive_only = create(:issue, repository: repository, number: 2, pull_request: true, node_id: nil)
    matches_issue = create(:issue, repository: repository, number: 3, pull_request: true, node_id: nil)
    create(:issue, repository: repository, number: 3, pull_request: false, node_id: 'I_3')
    other_repository = create(:repository, host: host)
    create(:issue, repository: other_repository, number: 2, pull_request: true, node_id: 'PR_2')

    other_host = create(:host, kind: 'gitlab')
    gitlab_repository = create(:repository, host: other_host)
    gitlab_row = create(:issue, repository: gitlab_repository, number: 1, pull_request: true, node_id: nil)
    create(:issue, repository: gitlab_repository, number: 1, pull_request: true, node_id: 'MR_1')

    progress = []
    deleted = Issue.delete_gharchive_duplicates(host, batch_size: 2) { |next_id, total| progress << [next_id, total] }

    assert_equal 1, deleted
    refute Issue.exists?(duplicate.id)
    assert Issue.exists?(archive_only.id)
    assert Issue.exists?(matches_issue.id)
    assert Issue.exists?(gitlab_row.id)
    assert_operator progress.size, :>, 1
    assert_equal 1, progress.last.last
  end

  test "delete_gharchive_duplicates starts from the given id" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    before = create(:issue, repository: repository, number: 1, pull_request: true, node_id: nil)
    create(:issue, repository: repository, number: 1, pull_request: true, node_id: 'PR_1')
    after = create(:issue, repository: repository, number: 2, pull_request: true, node_id: nil)
    create(:issue, repository: repository, number: 2, pull_request: true, node_id: 'PR_2')

    assert_equal 1, Issue.delete_gharchive_duplicates(host, from_id: after.id)
    assert Issue.exists?(before.id)
    refute Issue.exists?(after.id)
  end
end
