require 'test_helper'

class RepositoryTest < ActiveSupport::TestCase
  test "sync_pending? is true before a repository completes its first sync" do
    repository = create(:repository, last_synced_at: nil)

    assert_predicate repository, :sync_pending?
  end

  test "sync_pending? is false for a synced repository with no issues" do
    repository = create(:repository, last_synced_at: Time.current, issues_count: 0, pull_requests_count: 0)

    refute_predicate repository, :sync_pending?
  end

  test "sync_pending? is false for a repository with a terminal status" do
    repository = create(:repository, status: 'not_found', last_synced_at: nil)

    refute_predicate repository, :sync_pending?
  end

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
    reconciliation = repository.reconciliation
    repository.stubs(:reconciliation).returns(reconciliation)
    reconciliation.expects(:complete).once

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
    reconciliation = repository.reconciliation
    repository.stubs(:reconciliation).returns(reconciliation)
    reconciliation.expects(:complete).once

    repository.reconcile

    repository.reload
    assert_equal [21, 90, 91], repository.issues.where(user: 'mootari').order(:number).pluck(:number)
    assert_equal 3, repository.issues_count
    assert_empty repository.issues.maintainers.where(user: 'mootari')
  end

  test "incremental GitHub sync closes a pull request merged since it was first seen" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'opencollective/opencollective-api', last_synced_at: 2.days.ago)
    create(:issue, repository: repository, host: host, uuid: '5731355752', number: 12270, pull_request: true,
           state: 'open', merged_at: nil, created_at: 10.days.ago, updated_at: 3.days.ago)
    merged_at = 1.day.ago.utc.change(usec: 0)

    Hosts::Github.any_instance.stubs(:fetch_random_token).returns('token')
    stub_request(:get, %r{\Ahttps://api\.github\.com/repos/opencollective/opencollective-api/issues\?.*since=})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: [{
          id: 5731355752, node_id: 'PR_kwDOAiM0fc8AAAABG8qx-g', number: 12270, title: 'Fix', state: 'closed',
          locked: false, comments: 0, created_at: 10.days.ago.iso8601, updated_at: merged_at.iso8601,
          closed_at: merged_at.iso8601, user: { login: 'author' }, labels: [], assignees: [],
          author_association: 'MEMBER', state_reason: nil,
          pull_request: { url: 'https://api.github.com/repos/opencollective/opencollective-api/pulls/12270', merged_at: merged_at.iso8601 }
        }].to_json
      )

    repository.sync_issues

    issue = repository.issues.find_by(number: 12270)
    assert_equal 1, repository.issues.where(number: 12270).count
    assert_equal 'closed', issue.state
    assert_equal merged_at, issue.merged_at
    assert_equal merged_at, issue.updated_at
    assert_in_delta Time.current, repository.reload.last_synced_at, 5
  end

  test "GitHub sync takes over a row whose uuid collides with another repository's pull id" do
    host = create_or_find_github_host
    other = create(:repository, host: host, full_name: 'opencollective/opencollective-api')
    create(:issue, repository: other, host: host, uuid: '1955804752', number: 10190, pull_request: true, node_id: nil)
    repository = create(:repository, host: host, full_name: 'cym13/dirduster', last_synced_at: 2.days.ago)

    Hosts::Github.any_instance.stubs(:fetch_random_token).returns('token')
    stub_request(:get, %r{\Ahttps://api\.github\.com/repos/cym13/dirduster/issues\?.*since=})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: [{
          id: 1955804752, node_id: 'I_kwDOBHYdHs50kzZQ', number: 8, title: 'dirduster crashes on start (ubuntu22)',
          state: 'open', locked: false, comments: 0, created_at: 2.years.ago.iso8601, updated_at: 1.day.ago.iso8601,
          closed_at: nil, user: { login: 'author' }, labels: [], assignees: [], author_association: 'NONE', state_reason: nil
        }].to_json
      )

    repository.sync_issues

    assert_equal [8], repository.issues.pluck(:number)
    assert_in_delta 2.years.ago, repository.issues.first.created_at, 5
    assert_empty other.issues
  end

  test "GitHub sync removes the GH Archive row for a pull request it fetched" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'opencollective/opencollective-api', last_synced_at: 2.days.ago)
    create(:issue, repository: repository, host: host, uuid: '2849826733', number: 12270, pull_request: true, node_id: nil, state: 'open')
    create(:issue, repository: repository, host: host, uuid: '2849826999', number: 12271, pull_request: true, node_id: nil, state: 'open')

    Hosts::Github.any_instance.stubs(:fetch_random_token).returns('token')
    stub_request(:get, %r{\Ahttps://api\.github\.com/repos/opencollective/opencollective-api/issues\?.*since=})
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: [{
          id: 3441334628, node_id: 'PR_kwDOBFhNgM6xyz', number: 12270, title: 'Fix expense flow',
          state: 'closed', locked: false, comments: 0, created_at: 2.weeks.ago.iso8601, updated_at: 1.day.ago.iso8601,
          closed_at: 1.day.ago.iso8601, user: { login: 'author' }, labels: [], assignees: [], author_association: 'MEMBER',
          state_reason: nil, pull_request: { merged_at: 1.day.ago.iso8601 }
        }].to_json
      )

    repository.sync_issues

    assert_equal [['3441334628', 'closed']], repository.issues.where(number: 12270).pluck(:uuid, :state)
    assert_equal ['2849826999'], repository.issues.where(number: 12271).pluck(:uuid)
  end

  test "GitLab sync leaves a row with a colliding uuid in its repository" do
    host = create(:host, kind: 'gitlab', name: 'gitlab.com', url: 'https://gitlab.com')
    other = create(:repository, host: host, full_name: 'group/other')
    create(:issue, repository: other, host: host, uuid: '1234', number: 5, pull_request: false)
    repository = create(:repository, host: host, full_name: 'group/project', last_synced_at: 2.days.ago)

    Hosts::Gitlab.any_instance.stubs(:load_issues).yields([{
      uuid: 1234, number: 9, title: 'Merge request', state: 'opened', locked: false, comments_count: 0,
      created_at: 1.week.ago, updated_at: 1.day.ago, closed_at: nil, user: 'author', labels: [], assignees: [],
      pull_request: true
    }])

    repository.sync_issues

    assert_empty repository.issues
    assert_equal 1, other.issues.count
  end

  test "sync_issues sets the cursor to when the sync started" do
    host = create(:host)
    repository = create(:repository, host: host, last_synced_at: 2.days.ago)
    started_at = Time.current.change(usec: 0)
    host_api = mock
    host_api.expects(:load_issues).with(repository).with { travel 10.minutes; true }
    host.expects(:host_instance).returns(host_api)

    travel_to(started_at) { repository.sync_issues }

    assert_equal started_at, repository.reload.last_synced_at
  end

  test "failed sync keeps the previous cursor" do
    host = create(:host)
    last_synced_at = 2.days.ago.change(usec: 0)
    repository = create(:repository, host: host, last_synced_at: last_synced_at)
    host_api = mock
    host_api.expects(:load_issues).raises(Faraday::TimeoutError)
    host.expects(:host_instance).returns(host_api)

    assert_raises(Faraday::TimeoutError) { repository.sync_issues }

    repository.reload
    assert_equal 'error', repository.status
    assert_equal last_synced_at, repository.last_synced_at
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
