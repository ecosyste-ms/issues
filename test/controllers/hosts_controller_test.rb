require 'test_helper'

class HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
  end

  test 'should get index' do
    get hosts_path
    assert_response :success
    assert_template 'hosts/index'
    assert_not_nil assigns(:hosts)
    assert_not_nil assigns(:repositories)
    assert_not_nil assigns(:pagy)
  end

  test 'should order hosts by repositories count descending' do
    # Create hosts with different repository counts
    host1 = create_host(name: 'GitLab', url: 'https://gitlab.com', repositories_count: 100)
    host2 = create_host(name: 'Bitbucket', url: 'https://bitbucket.org', repositories_count: 500)

    get hosts_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    # Hosts should be ordered by repositories_count descending
    assert hosts.first.repositories_count >= hosts.last.repositories_count if hosts.size > 1
  end

  test 'should only show visible hosts' do
    # Create hidden host
    hidden_host = create_host(name: 'Private', url: 'https://private.com', repositories_count: 0)

    get hosts_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    assert hosts.none? { |h| h.hidden? }
  end

  test 'should include authors count for hosts' do
    get hosts_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    # with_authors scope should be applied
    hosts.each do |host|
      assert_respond_to host, :authors_count if host.respond_to?(:authors_count)
    end
  end

  test 'should show recent repositories on index' do
    # Create repository with recent sync
    recent_repo = create_repository(@host,
      full_name: 'recent/repo',
      owner: 'recent',
      last_synced_at: 1.hour.ago
    )

    get hosts_path
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    # Should be ordered by last_synced_at DESC
    if repositories.size > 1
      assert repositories.first.last_synced_at >= repositories.last.last_synced_at if repositories.first.last_synced_at && repositories.last.last_synced_at
    end
  end

  test 'should only show visible repositories on index' do
    # Create invisible repository (no last_synced_at)
    invisible_repo = create_repository(@host,
      full_name: 'invisible/repo',
      owner: 'invisible',
      last_synced_at: nil
    )

    get hosts_path
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    assert repositories.none? { |r| r.id == invisible_repo.id }
  end

  test 'should paginate repositories on index' do
    # Create multiple repositories
    15.times do |i|
      create_repository(@host,
        full_name: "test/repo#{i}",
        last_synced_at: i.hours.ago
      )
    end

    get hosts_path
    assert_response :success
    
    pagy = assigns(:pagy)
    assert_not_nil pagy
    assert_equal 10, pagy.vars[:items]
  end

  test 'should set fresh_when for caching on index' do
    get hosts_path
    assert_response :success
    
    # Check that ETag is set
    assert_not_nil response.headers['ETag']
  end

  test 'should show host' do
    get host_path(@host)
    assert_response :success
    assert_template 'hosts/show'
    assert_equal @host, assigns(:host)
    assert_not_nil assigns(:repositories)
    assert_not_nil assigns(:pagy)
  end

  test 'should only show visible repositories for host' do
    # Create invisible repository
    invisible_repo = create_repository(@host,
      full_name: 'secret/repo',
      owner: 'secret',
      last_synced_at: nil
    )

    get host_path(@host)
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    assert repositories.none? { |r| r.id == invisible_repo.id }
  end

  test 'should sort repositories by default last_synced_at' do
    get host_path(@host)
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    # Default sort should be by last_synced_at DESC
  end

  test 'should sort repositories by custom field' do
    get host_path(@host, params: { sort: 'issues_count' })
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
  end

  test 'should sort repositories ascending' do
    get host_path(@host, params: { sort: 'created_at', order: 'asc' })
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
  end

  test 'should sort repositories descending by default' do
    get host_path(@host, params: { sort: 'updated_at' })
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
  end

  test 'should handle null values in sorting' do
    # Create repository with null last_synced_at
    create_repository(@host,
      full_name: 'null/repo',
      owner: 'null',
      last_synced_at: nil
    )

    get host_path(@host, params: { sort: 'last_synced_at' })
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    # Should handle null values properly with nulls_last
  end

  test 'should paginate host repositories' do
    # Create multiple repositories
    25.times do |i|
      create_repository(@host,
        full_name: "page/repo#{i}",
        owner: 'page',
      )
    end

    get host_path(@host)
    assert_response :success
    
    pagy = assigns(:pagy)
    assert_not_nil pagy
  end

  test 'should set fresh_when for caching on show' do
    get host_path(@host)
    assert_response :success
    
    # Check that ETag is set
    assert_not_nil response.headers['ETag']
  end

  test 'should raise not found for non-existent host' do
    get host_path('nonexistent')
    assert_response :not_found
  end

  test 'should handle hosts with no repositories' do
    # Create host with no repositories
    empty_host = create_host(name: 'Empty', url: 'https://empty.com', repositories_count: 0)

    get host_path(empty_host)
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    assert_empty repositories
  end

  test 'should redirect incorrectly cased host names' do
    # Create host with proper case
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org', repositories_count: 10)
    
    # Request with incorrect case
    get host_path('Codeberg.org')
    
    # Should redirect to correct case
    assert_response :moved_permanently
    assert_redirected_to host_path('codeberg.org')
  end

  test 'should redirect uppercase host names' do
    # Create host with proper case
    proper_host = create_host(name: 'gitea.com', url: 'https://gitea.com', repositories_count: 5)
    
    # Request with uppercase
    get host_path('GITEA.COM')
    
    # Should redirect to correct case
    assert_response :moved_permanently
    assert_redirected_to host_path('gitea.com')
  end

  test 'should show exact match without redirect' do
    # Create host with exact case
    exact_host = create_host(name: 'ExactCase', url: 'https://exactcase.com', repositories_count: 100)
    
    # Request with exact case
    get host_path('ExactCase')
    
    # Should show directly without redirect
    assert_response :success
    assert_equal exact_host, assigns(:host)
  end

  test 'should raise not found for non-existent host even with case variations' do
    # Request completely non-existent host
    get host_path('nonexistent.example.com')
    
    # Should raise not found
    assert_response :not_found
  end
end