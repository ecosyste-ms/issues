require 'test_helper'

class Api::V1::HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
  end

  test 'index returns all visible hosts' do
    # Create additional hosts
    gitlab = create_host(name: 'GitLab', url: 'https://gitlab.com', repositories_count: 100)
    bitbucket = create_host(name: 'Bitbucket', url: 'https://bitbucket.org', repositories_count: 50)
    
    get api_v1_hosts_path, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    assert json.size >= 3
    
    host_names = json.map { |h| h['name'] }
    assert_includes host_names, 'GitHub'
    assert_includes host_names, 'GitLab'
    assert_includes host_names, 'Bitbucket'
  end

  test 'index orders hosts by repositories_count descending' do
    # Create hosts with different repository counts
    small_host = create_host(name: 'SmallHost', url: 'https://small.com', repositories_count: 10)
    large_host = create_host(name: 'LargeHost', url: 'https://large.com', repositories_count: 1000)
    
    get api_v1_hosts_path, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    repo_counts = json.map { |h| h['repositories_count'] }
    
    # Verify descending order
    assert_equal repo_counts, repo_counts.sort.reverse
  end

  test 'index only shows visible hosts' do
    # Host.visible scope filters out hosts with repositories_count = 0
    hidden_host = create_host(name: 'HiddenHost', url: 'https://hidden.com', repositories_count: 0)
    
    get api_v1_hosts_path, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    host_names = json.map { |h| h['name'] }
    assert_not_includes host_names, 'HiddenHost'
  end

  test 'index respects cache headers' do
    get api_v1_hosts_path, as: :json
    assert_response :success
    
    etag = response.headers['ETag']
    assert etag.present?
    
    # Request again with If-None-Match
    get api_v1_hosts_path, headers: { 'If-None-Match': etag }, as: :json
    assert_response :not_modified
  end

  test 'show returns host details' do
    get api_v1_host_path(@host), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @host.name, json['name']
    assert_equal @host.url, json['url']
    assert_equal @host.repositories_count, json['repositories_count']
    if @host.issues_count.nil?
      assert_nil json['issues_count']
    else
      assert_equal @host.issues_count, json['issues_count']
    end
  end

  test 'show handles exact case match' do
    get api_v1_host_path(@host.name), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @host.name, json['name']
  end

  test 'show raises not found for non-existent host' do
    get api_v1_host_path('NonExistentHost'), as: :json
    assert_response :not_found
  end

  test 'show respects cache headers' do
    get api_v1_host_path(@host), as: :json
    assert_response :success
    
    etag = response.headers['ETag']
    assert etag.present?
    
    # Request again with If-None-Match
    get api_v1_host_path(@host), headers: { 'If-None-Match': etag }, as: :json
    assert_response :not_modified
  end

  test 'should redirect incorrectly cased host in API' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    
    get api_v1_host_path('Codeberg.org'), as: :json
    
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path('codeberg.org')
  end

  test 'should redirect uppercase host in API' do
    proper_host = create_host(name: 'gitea.com', url: 'https://gitea.com')
    
    get api_v1_host_path('GITEA.COM'), as: :json
    
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path('gitea.com')
  end

  test 'should show host with exact match without redirect' do
    proper_host = create_host(name: 'exact.host', url: 'https://exact.host')
    
    get api_v1_host_path('exact.host'), as: :json
    
    assert_response :success
    assert_equal proper_host, assigns(:host)
  end
end