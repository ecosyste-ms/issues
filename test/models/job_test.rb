require 'test_helper'

class JobTest < ActiveSupport::TestCase
  test "sync_issues marks repository as not_found and raises error when repos service returns 404" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')

    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})

    error = assert_raises(RuntimeError) do
      job.sync_issues
    end

    assert_match /Repository not found in repos service/, error.message
    repo = host.repositories.find_by('lower(full_name) = ?', 'test-org/test-repo')
    assert_not_nil repo
    assert_equal 'not_found', repo.status
  end

  test "sync_issues marks existing repository as not_found and raises error when repos service returns 404" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    existing_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: nil)
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')

    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})

    error = assert_raises(RuntimeError) do
      job.sync_issues
    end

    assert_match /Repository not found in repos service/, error.message
    existing_repo.reload
    assert_equal 'not_found', existing_repo.status
  end

  test "sync_issues continues normally when repos service returns 200" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')

    response_body = {
      'host' => { 'name' => 'GitLab' },
      'full_name' => 'test-org/test-repo',
      'default_branch' => 'main',
      'owner' => 'test-org',
      'status' => nil
    }.to_json

    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

    Repository.any_instance.expects(:sync_issues).once

    result = job.sync_issues

    assert_not_nil result
    repo = host.repositories.find_by('lower(full_name) = ?', 'test-org/test-repo')
    assert_not_nil repo
    assert_nil repo.status
  end

  test "sync_issues returns nil for non-404 error responses" do
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')

    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 500, body: '', headers: {})

    result = job.sync_issues

    assert_nil result
  end

  test "active scope excludes repositories with not_found status" do
    host = create(:host)
    active_repo = create(:repository, host: host, status: nil)
    not_found_repo = create(:repository, host: host, status: 'not_found')
    error_repo = create(:repository, host: host, status: 'error')

    active_repos = Repository.active

    assert_includes active_repos, active_repo
    assert_not_includes active_repos, not_found_repo
    assert_not_includes active_repos, error_repo
  end

  test "sync_issues raises error for repos already marked as not_found without making API call" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    not_found_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: 'not_found')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')

    # Should not make any API call
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 200, body: '{}', headers: {})

    error = assert_raises(RuntimeError) do
      job.sync_issues
    end

    assert_match /is marked as not_found/, error.message

    # Verify the API was never called
    assert_not_requested :get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo"

    # Status should remain not_found
    not_found_repo.reload
    assert_equal 'not_found', not_found_repo.status
  end

  test "perform_issue_syncing marks job as error when repository is not_found" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    not_found_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: 'not_found')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo', status: 'pending')

    job.perform_issue_syncing

    job.reload
    assert_equal 'error', job.status
    assert_match /is marked as not_found/, job.results['error']
  end

  test "perform_issue_syncing marks job as error when repos service returns 404" do
    host = create(:host, name: 'GitLab', url: 'https://gitlab.com')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo', status: 'pending')

    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})

    job.perform_issue_syncing

    job.reload
    assert_equal 'error', job.status
    assert_match /Repository not found in repos service/, job.results['error']

    # Verify repo was marked as not_found
    repo = host.repositories.find_by('lower(full_name) = ?', 'test-org/test-repo')
    assert_equal 'not_found', repo.status
  end
end
