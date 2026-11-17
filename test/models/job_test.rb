require 'test_helper'

class JobTest < ActiveSupport::TestCase
  setup do
    REDIS.stubs(:get).returns(nil)
    stub_request(:get, 'https://gitlab.com/api/v4/projects/test-org%2Ftest-repo')
      .to_return(status: 404, body: { message: '404 Project Not Found' }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  test "sync_issues leaves a repository the forge still has active when repos hasn't indexed it" do
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
    existing_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: nil)
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})
    stub_request(:get, 'https://gitlab.com/api/v4/projects/test-org%2Ftest-repo')
      .to_return(status: 200, body: { id: 1, path_with_namespace: 'test-org/test-repo' }.to_json, headers: { 'Content-Type' => 'application/json' })

    error = assert_raises(RuntimeError) { job.sync_issues }

    assert_match /not yet indexed/, error.message
    assert_nil existing_repo.reload.status
  end

  test "sync_issues checks GitHub before marking a repository not_found" do
    host = create_or_find_github_host
    existing_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: nil)
    job = create(:job, url: 'https://github.com/test-org/test-repo')
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})
    Hosts::Github.any_instance.stubs(:fetch_random_token).returns('token')
    stub_request(:get, 'https://api.github.com/repos/test-org/test-repo')
      .to_return(status: 200, body: { full_name: 'test-org/test-repo' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(RuntimeError) { job.sync_issues }
    assert_nil existing_repo.reload.status

    stub_request(:get, 'https://api.github.com/repos/test-org/test-repo').to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })

    assert_raises(RuntimeError) { job.sync_issues }
    assert_equal 'not_found', existing_repo.reload.status
  end

  test "sync_issues checks Gitea before marking a repository not_found" do
    host = create(:host, name: 'codeberg.org', kind: 'gitea', url: 'https://codeberg.org')
    existing_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: nil)
    job = create(:job, url: 'https://codeberg.org/test-org/test-repo')
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://codeberg.org/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})
    stub_request(:get, 'https://codeberg.org/api/v1/repos/test-org/test-repo')
      .to_return(status: 200, body: { full_name: 'test-org/test-repo' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(RuntimeError) { job.sync_issues }
    assert_nil existing_repo.reload.status
  end

  test "sync_issues marks a repository on a host without a forge check not_found" do
    host = create(:host, name: 'bitbucket.org', kind: 'bitbucket', url: 'https://bitbucket.org')
    job = create(:job, url: 'https://bitbucket.org/test-org/test-repo')
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://bitbucket.org/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})

    assert_raises(RuntimeError) { job.sync_issues }
    assert_equal 'not_found', host.repositories.find_by!(full_name: 'test-org/test-repo').status
  end

  test "sync_issues leaves the repository active when the forge check fails" do
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
    existing_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: nil)
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo')
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://gitlab.com/test-org/test-repo")
      .to_return(status: 404, body: '', headers: {})
    stub_request(:get, 'https://gitlab.com/api/v4/projects/test-org%2Ftest-repo')
      .to_return(status: 500, body: { message: '500' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(::Gitlab::Error::InternalServerError) { job.sync_issues }
    assert_nil existing_repo.reload.status
  end
  test "sync_issues marks repository as not_found and raises error when repos service returns 404" do
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
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
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
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
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
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

  test "sync_issues reconciles an existing repository without the repos service" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'observablehq/notebook-kit')
    job = create(:job, url: repository.html_url)

    Repository.any_instance.expects(:reconcile).once

    assert_not_nil job.sync_issues(full: true)
    assert_not_requested :get, /repos\.ecosyste\.ms/
  end

  test "sync_issues_async includes the full reconciliation worker argument" do
    job = create(:job)
    SyncIssuesWorker.expects(:perform_async).with(job.id, true).returns('full-sync-job-id')

    job.sync_issues_async(false, full: true)

    assert_equal 'full-sync-job-id', job.reload.sidekiq_id
  end

  test "failed full reconciliation clears the repository throttle" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, full_name: 'observablehq/notebook-kit')
    job = create(:job, url: repository.html_url)
    reconciliation = mock

    Repository.any_instance.expects(:reconcile).raises(StandardError.new('GitHub unavailable'))
    Repository.any_instance.expects(:reconciliation).returns(reconciliation)
    reconciliation.expects(:clear).once

    assert_raises(StandardError) { job.sync_issues(full: true) }
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
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
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
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
    not_found_repo = create(:repository, host: host, full_name: 'test-org/test-repo', status: 'not_found')
    job = create(:job, url: 'https://gitlab.com/test-org/test-repo', status: 'pending')

    job.perform_issue_syncing

    job.reload
    assert_equal 'error', job.status
    assert_match /is marked as not_found/, job.results['error']
  end

  test "perform_issue_syncing marks job as error when repos service returns 404" do
    host = create(:host, name: 'GitLab', kind: 'gitlab', url: 'https://gitlab.com')
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
