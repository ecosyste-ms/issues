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

  test "github_node_repository_id decodes the repository id from new-format node ids" do
    assert_equal 35861629, Issue.github_node_repository_id('PR_kwDOAiM0fc6p3Oet')
    assert_equal 76222279, Issue.github_node_repository_id('PR_kwDOBIsPR86mTjNS')
    assert_equal 193140650, Issue.github_node_repository_id('PR_kwDOC4MXqs5QpOOO')
    assert_equal 1234, Issue.github_node_repository_id(node_id(1234, 1))
    assert_nil Issue.github_node_repository_id('MDExOlB1bGxSZXF1ZXN0NDk0NDM4NjM=')
    assert_nil Issue.github_node_repository_id('PR_!!')
    assert_nil Issue.github_node_repository_id(nil)
  end

  test "delete_misplaced_github_rows deletes rows whose node id belongs to another repository" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    own = (1..10).map { |n| create(:issue, repository: repository, number: n, node_id: node_id(35861629, n)) }
    misplaced = create(:issue, repository: repository, number: 1, pull_request: true, node_id: node_id(193140650, 99))
    unpaired = create(:issue, repository: repository, number: 99, node_id: node_id(193140650, 98))
    legacy = create(:issue, repository: repository, number: 100, node_id: 'MDExOlB1bGxSZXF1ZXN0NDk0NDM4NjM=')

    tied = create(:repository, host: host)
    tied_rows = [create(:issue, repository: tied, number: 1, node_id: node_id(1, 1)), create(:issue, repository: tied, number: 1, node_id: node_id(2, 1))]

    assert_equal 2, Issue.delete_misplaced_github_rows(host, batch_size: 3)
    refute Issue.exists?(misplaced.id)
    refute Issue.exists?(unpaired.id)
    assert Issue.exists?(legacy.id)
    assert own.all? { |i| Issue.exists?(i.id) }
    assert tied_rows.all? { |i| Issue.exists?(i.id) }
  end

  test "delete_misplaced_github_rows finds the repository id among mostly legacy node ids" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    Issue.insert_all((1..120).map { |n|
      { host_id: host.id, repository_id: repository.id, uuid: "legacy-#{n}", number: n, node_id: Base64.strict_encode64("011:PullRequest#{n}"),
        pull_request: true, created_at: Time.current, updated_at: Time.current }
    })
    legacy = repository.issues.where("node_id LIKE 'MD%'").to_a
    (200..209).each { |n| create(:issue, repository: repository, number: n, node_id: node_id(35861629, n)) }
    misplaced = create(:issue, repository: repository, number: 1, node_id: node_id(193140650, 99))

    assert_equal 1, Issue.delete_misplaced_github_rows(host)
    refute Issue.exists?(misplaced.id)
    assert legacy.all? { |i| Issue.exists?(i.id) }
  end

  test "delete_misplaced_github_rows skips the repository lookup for legacy node ids" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    legacy = create(:issue, repository: repository, number: 1, node_id: 'MDExOlB1bGxSZXF1ZXN0NDk0NDM4NjM=')
    Issue.expects(:github_repository_id_for).never

    assert_equal 0, Issue.delete_misplaced_github_rows(host)
    assert Issue.exists?(legacy.id)
  end

  test "delete_misplaced_github_rows skips repositories without a clear majority" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    own = (1..7).map { |n| create(:issue, repository: repository, number: n, node_id: node_id(35861629, n)) }
    foreign = (1..5).map { |n| create(:issue, repository: repository, number: n, node_id: node_id(193140650 + n, n)) }

    assert_equal 0, Issue.delete_misplaced_github_rows(host)
    assert (own + foreign).all? { |i| Issue.exists?(i.id) }
  end

  test "delete_misplaced_github_rows leaves a row a concurrent sync has moved" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    (1..10).each { |n| create(:issue, repository: repository, number: n, node_id: node_id(35861629, n)) }
    misplaced = create(:issue, repository: repository, number: 1, node_id: node_id(193140650, 99))
    home = create(:repository, host: host)
    Issue.stubs(:github_repository_id_for).with { misplaced.update_column(:repository_id, home.id) }.returns(35861629)

    assert_equal 0, Issue.delete_misplaced_github_rows(host)
    assert_equal home.id, misplaced.reload.repository_id
  end

  def node_id(repository_id, id)
    'PR_' + Base64.urlsafe_encode64([0x93, 0x00, 0xce, *[repository_id].pack('N').bytes, 0xce, *[id].pack('N').bytes].pack('C*'), padding: false)
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
