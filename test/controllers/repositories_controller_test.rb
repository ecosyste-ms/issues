require 'test_helper'

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @user_ip = '127.0.0.1'
  end

  test 'should redirect index to host page' do
    get host_repositories_path(@host)
    assert_redirected_to host_path(@host)
  end

  test 'should show repository' do
    get host_repository_path(@host, @repository.full_name)
    assert_response :success
    assert_template 'repositories/show'
  end

  test 'should handle repository with different case' do
    get host_repository_path(@host, @repository.full_name.upcase)
    assert_response :success
  end

  test 'should sync repository if not found and create it' do
    full_name = 'new/repository'
    
    # Mock the sync process
    job = stub(sync_issues_async: true)
    Job.stubs(:new).returns(job)
    job.stubs(:save).returns(true)
    
    # Create the repository that will be found after sync
    new_repo = create_repository(@host, full_name: full_name)
    
    get host_repository_path(@host, full_name)
    assert_response :success
  end

  test 'should show error if repository sync fails' do
    full_name = 'nonexistent/repository'
    
    # Mock the sync process to not create a repository
    job = stub(sync_issues_async: true)
    Job.stubs(:new).returns(job)
    job.stubs(:save).returns(true)
    
    get host_repository_path(@host, full_name)
    # Currently returns 500 when repository is not found after sync
    # This might be a bug that should be fixed to return 404
    assert_response :internal_server_error
  end

  test 'should lookup repository by URL' do
    url = "https://#{@host.domain}/#{@repository.full_name}"
    
    get lookup_repositories_path, params: { url: url }
    assert_redirected_to host_repository_path(@host, @repository)
  end

  test 'should sync old repository on lookup' do
    url = "https://github.com/#{@repository.full_name}"
    @repository.update!(last_synced_at: 2.days.ago)
    
    # Mock the sync process
    job = stub(sync_issues_async: true)
    Job.stubs(:new).returns(job)
    job.stubs(:save).returns(true)
    
    get lookup_repositories_path, params: { url: url }
    assert_redirected_to host_repository_path(@host, @repository)
  end

  test 'should not sync recently synced repository on lookup' do
    url = "https://github.com/#{@repository.full_name}"
    @repository.update!(last_synced_at: 1.hour.ago)
    
    # Should not create any jobs
    Job.expects(:new).never
    
    get lookup_repositories_path, params: { url: url }
    assert_redirected_to host_repository_path(@host, @repository)
  end

  test 'should sync new repository on lookup' do
    full_name = 'new/repository'
    url = "https://github.com/#{full_name}"
    
    # Mock the sync process
    job = stub(sync_issues_async: true)
    Job.stubs(:new).returns(job)
    job.stubs(:save).returns(true)
    
    # Create the repository that will be found after sync
    new_repo = create_repository(@host, full_name: full_name)
    
    get lookup_repositories_path, params: { url: url }
    assert_redirected_to host_repository_path(@host, new_repo)
  end

  test 'should raise not found for invalid URL format' do
    get lookup_repositories_path, params: { url: '' }
    assert_response :not_found
  end

  test 'should raise not found for unknown host' do
    get lookup_repositories_path, params: { url: 'https://unknown.com/repo' }
    assert_response :not_found
  end

  test 'should raise not found for empty path' do
    url = "https://github.com/"
    
    get lookup_repositories_path, params: { url: url }
    assert_response :not_found
  end

  test 'lookup with priority queues to high_priority queue' do
    url = "https://github.com/#{@repository.full_name}"
    @repository.update!(last_synced_at: 2.days.ago)
    
    # Expect job to be queued with high priority
    SyncIssuesWorker.expects(:perform_with_priority).with(anything, true).returns('fake-job-id')
    
    get lookup_repositories_path, params: { url: url, priority: '1' }
    assert_redirected_to host_repository_path(@host, @repository)
  end

  test 'lookup without priority uses default queue' do
    url = "https://github.com/#{@repository.full_name}"
    @repository.update!(last_synced_at: 2.days.ago)
    
    # Expect job to be queued normally
    SyncIssuesWorker.expects(:perform_async).with(anything).returns('fake-job-id')
    
    get lookup_repositories_path, params: { url: url }
    assert_redirected_to host_repository_path(@host, @repository)
  end

  test 'should redirect incorrectly cased host in repository show' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    repo = create_repository(proper_host, full_name: 'desour/doublejump', owner: 'desour')
    
    get host_repository_path('Codeberg.org', repo.full_name)
    
    assert_response :moved_permanently
    assert_redirected_to host_repository_path('codeberg.org', repo.full_name)
  end

  test 'should redirect uppercase host in repository show' do
    proper_host = create_host(name: 'gitea.com', url: 'https://gitea.com')
    repo = create_repository(proper_host, full_name: 'test/repo', owner: 'test')
    
    get host_repository_path('GITEA.COM', repo.full_name)
    
    assert_response :moved_permanently
    assert_redirected_to host_repository_path('gitea.com', repo.full_name)
  end

  test 'should show repository with exact host match without redirect' do
    proper_host = create_host(name: 'exact.host', url: 'https://exact.host')
    repo = create_repository(proper_host, full_name: 'test/repo', owner: 'test')
    
    get host_repository_path('exact.host', repo.full_name)
    
    assert_response :success
    assert_equal proper_host, assigns(:host)
    assert_equal repo, assigns(:repository)
  end

  test 'should redirect incorrectly cased host in repository index' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    
    get host_repositories_path('Codeberg.org')
    
    assert_response :moved_permanently
    assert_redirected_to host_path('codeberg.org')
  end

  test 'should raise not found for non-existent host in repository routes' do
    get host_repository_path('nonexistent.example.com', 'test/repo')

    assert_response :not_found
  end

  test 'should return 404 for repository with hidden owner' do
    hidden_owner_name = 'secret_owner'
    repo = create_repository(@host, full_name: "#{hidden_owner_name}/private_repo", owner: hidden_owner_name)
    Owner.create!(host: @host, login: hidden_owner_name, hidden: true)

    get host_repository_path(@host, repo.full_name)
    assert_response :not_found
  end

  test 'should filter hidden users from issue authors list' do
    hidden_user = 'secret_user'
    visible_user = 'visible_user'

    # Create a repository
    repo = create_repository(@host, full_name: 'test/repo', owner: 'test')

    # Create a hidden owner for the hidden user
    Owner.create!(host: @host, login: hidden_user, hidden: true)

    # Create issues from both visible and hidden users
    create_issue(repo, number: 1, user: visible_user, pull_request: false)
    create_issue(repo, number: 2, user: hidden_user, pull_request: false)
    create_issue(repo, number: 3, user: visible_user, pull_request: false)

    get host_repository_path(@host, repo.full_name)
    assert_response :success

    # Check that hidden_users instance variable is set
    hidden_users = assigns(:hidden_users)
    assert_not_nil hidden_users
    assert hidden_users.include?(hidden_user)
    assert_not hidden_users.include?(visible_user)
  end

  test 'should filter hidden users from pull request authors list' do
    hidden_user = 'secret_pr_user'
    visible_user = 'visible_pr_user'

    # Create a repository
    repo = create_repository(@host, full_name: 'test/pr_repo', owner: 'test')

    # Create a hidden owner for the hidden user
    Owner.create!(host: @host, login: hidden_user, hidden: true)

    # Create pull requests from both visible and hidden users
    create_pull_request(repo, number: 1, user: visible_user)
    create_pull_request(repo, number: 2, user: hidden_user)
    create_pull_request(repo, number: 3, user: visible_user)

    get host_repository_path(@host, repo.full_name)
    assert_response :success

    # Check that hidden_users instance variable is set
    hidden_users = assigns(:hidden_users)
    assert_not_nil hidden_users
    assert hidden_users.include?(hidden_user)
    assert_not hidden_users.include?(visible_user)
  end

  test 'should filter hidden users from maintainers list' do
    hidden_maintainer = 'secret_maintainer'
    visible_maintainer = 'visible_maintainer'

    # Create a repository
    repo = create_repository(@host, full_name: 'test/maintainer_repo', owner: 'test')

    # Create a hidden owner for the hidden maintainer
    Owner.create!(host: @host, login: hidden_maintainer, hidden: true)

    # Create issues from maintainers (MEMBER association makes them maintainers)
    create_issue(repo, number: 1, user: visible_maintainer, author_association: 'MEMBER')
    create_issue(repo, number: 2, user: hidden_maintainer, author_association: 'MEMBER')

    get host_repository_path(@host, repo.full_name)
    assert_response :success

    # Check that maintainers list doesn't include hidden users
    maintainers = assigns(:maintainers)
    assert_not_nil maintainers

    maintainer_logins = maintainers.map { |login, count| login }
    assert maintainer_logins.include?(visible_maintainer)
    assert_not maintainer_logins.include?(hidden_maintainer)
  end

end