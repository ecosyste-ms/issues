require 'test_helper'

class Api::V1::RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    # Update last_synced_at to force sync
    @repository.update!(last_synced_at: 2.days.ago)
  end

  test 'lookup with priority queues to high_priority queue' do
    url = "https://github.com/#{@repository.full_name}"
    
    # Expect job to be queued with high priority
    SyncIssuesWorker.expects(:perform_with_priority).with(anything, true).returns('fake-job-id')
    
    get api_v1_repositories_lookup_path, params: { url: url, priority: '1' }
    assert_redirected_to api_v1_host_repository_path(@host, @repository)
  end

  test 'lookup without priority uses default queue' do
    url = "https://github.com/#{@repository.full_name}"
    
    # Expect job to be queued normally
    SyncIssuesWorker.expects(:perform_async).with(anything).returns('fake-job-id')
    
    get api_v1_repositories_lookup_path, params: { url: url }
    assert_redirected_to api_v1_host_repository_path(@host, @repository)
  end

  test 'ping with priority queues to high_priority queue' do
    # Expect job to be queued with high priority
    SyncIssuesWorker.expects(:perform_with_priority).with(anything, true).returns('fake-job-id')
    
    get ping_api_v1_host_repository_path(@host, @repository), params: { priority: '1' }
    assert_response :success
    assert_equal({ 'message' => 'pong' }, JSON.parse(response.body))
  end

  test 'ping without priority uses default queue' do
    # Expect job to be queued normally
    SyncIssuesWorker.expects(:perform_async).with(anything).returns('fake-job-id')
    
    get ping_api_v1_host_repository_path(@host, @repository)
    assert_response :success
    assert_equal({ 'message' => 'pong' }, JSON.parse(response.body))
  end
end