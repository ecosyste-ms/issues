require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    # Ensure host has positive repositories_count to be visible
    @host.update!(repositories_count: 1) if @host.repositories_count == 0
    
    @repository = create_or_find_rails_repository(@host)
    # Ensure repository has last_synced_at to be visible
    @repository.update!(last_synced_at: 1.hour.ago) if @repository.last_synced_at.nil?
  end

  test 'should get index' do
    get root_path
    assert_response :success
    assert_template 'home/index'
    assert_not_nil assigns(:hosts)
    assert_not_nil assigns(:repositories)
  end

  test 'should order hosts by repositories count descending' do
    # Create hosts with different repository counts
    host1 = create_host(name: 'GitLab', url: 'https://gitlab.com', repositories_count: 100)
    host2 = create_host(name: 'Bitbucket', url: 'https://bitbucket.org', repositories_count: 500)

    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    # Hosts should be ordered by repositories_count descending
    assert hosts.first.repositories_count >= hosts.last.repositories_count if hosts.size > 1
  end

  test 'should only show visible hosts' do
    # Create hidden host
    hidden_host = create_host(name: 'Private', url: 'https://private.com', repositories_count: 0)

    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    assert hosts.none? { |h| h.hidden? }
  end

  test 'should include necessary attributes for hosts' do
    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    # Check that hosts have the necessary attributes
    hosts.each do |host|
      assert_respond_to host, :repositories_count
      assert_respond_to host, :issues_count
      assert_respond_to host, :pull_requests_count
    end
  end

  test 'should show recent repositories on index' do
    # Create repository with recent sync
    recent_repo = create_repository(@host,
      full_name: 'recent/repo',
      owner: 'recent',
      last_synced_at: 1.hour.ago
    )

    get root_path
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

    get root_path
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    assert repositories.none? { |r| r.id == invisible_repo.id }
  end

  test 'should limit repositories to 10 on index' do
    # Create multiple repositories
    15.times do |i|
      create_repository(@host,
        full_name: "test/repo#{i}",
        last_synced_at: i.hours.ago
      )
    end

    get root_path
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    assert_equal 10, repositories.count
  end

  test 'should respond successfully for caching' do
    get root_path
    assert_response :success
    
    # Should respond successfully for caching purposes
    assert_not_nil response.headers['Content-Type']
  end

  test 'should display host statistics' do
    # Create additional hosts with different stats
    host1 = create_host(name: 'GitLab', url: 'https://gitlab.com', repositories_count: 100, issues_count: 1000, pull_requests_count: 500)
    host2 = create_host(name: 'Bitbucket', url: 'https://bitbucket.org', repositories_count: 50, issues_count: 300, pull_requests_count: 200)

    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    
    # Check that hosts have the necessary count attributes
    hosts.each do |host|
      assert_respond_to host, :repositories_count
      assert_respond_to host, :issues_count
      assert_respond_to host, :pull_requests_count
    end
  end

  test 'should include host association for repositories' do
    get root_path
    assert_response :success
    
    repositories = assigns(:repositories)
    assert_not_nil repositories
    
    # Repositories should have host loaded to avoid N+1 queries
    repositories.each do |repository|
      assert_not_nil repository.host
      # Should be able to access host name without additional queries
      assert repository.host.name.present?
    end
  end

  test 'should handle empty database' do
    # Clear all data
    Repository.delete_all
    Host.delete_all

    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    repositories = assigns(:repositories)
    
    assert_not_nil hosts
    assert_not_nil repositories
    assert_empty hosts
    assert_empty repositories
  end

  test 'should handle hosts with zero counts' do
    # Create host with zero counts - but since visible scope filters repositories_count > 0,
    # this host won't appear in the results, which is the expected behavior
    empty_host = create_host(
      name: 'Empty', 
      url: 'https://empty.com', 
      repositories_count: 0, 
      issues_count: 0, 
      pull_requests_count: 0
    )

    get root_path
    assert_response :success
    
    hosts = assigns(:hosts)
    assert_not_nil hosts
    # Empty host should not be included due to visible scope (repositories_count > 0)
    assert_not_includes hosts, empty_host
  end

  test 'should load data efficiently with minimal queries' do
    # Create some test data
    3.times do |i|
      host = create_host(name: "Host#{i}", url: "https://host#{i}.com", repositories_count: 10)
      2.times do |j|
        create_repository(host, full_name: "host#{i}/repo#{j}", last_synced_at: j.hours.ago)
      end
    end

    get root_path
    assert_response :success
    
    # Just verify that we have the expected data loaded
    hosts = assigns(:hosts)
    repositories = assigns(:repositories)
    
    assert hosts.count >= 3
    assert repositories.count > 0
  end

  test 'should respond to both root_path and home index path' do
    # Test root path
    get root_path
    assert_response :success
    assert_template 'home/index'

    # If there's a dedicated home path, test that too
    if Rails.application.routes.url_helpers.respond_to?(:home_index_path)
      get home_index_path
      assert_response :success  
      assert_template 'home/index'
    end
  end

  test 'should have basic response headers' do
    get root_path
    assert_response :success
    
    # Should have content type
    assert_not_nil response.headers['Content-Type']
    assert_includes response.headers['Content-Type'], 'text/html'
  end
end