require 'test_helper'

class Api::V1::JobsControllerTest < ActionDispatch::IntegrationTest
  test 'create job with valid url' do
    url = 'https://github.com/rails/rails'
    
    # Mock the async job
    Job.any_instance.expects(:parse_issues_async).once
    
    assert_difference 'Job.count', 1 do
      post api_v1_jobs_path, params: { url: url }, as: :json
    end
    
    job = Job.last
    assert_equal url, job.url
    assert_equal 'pending', job.status
    assert_redirected_to api_v1_job_path(job)
  end

  test 'create job returns error for missing url' do
    post api_v1_jobs_path, params: {}, as: :json
    assert_response :bad_request
    
    json = JSON.parse(response.body)
    assert_equal 'Bad Request', json['title']
    assert json['details'].is_a?(Array)
  end

  test 'create job returns error for invalid url' do
    post api_v1_jobs_path, params: { url: '' }, as: :json
    assert_response :bad_request
    
    json = JSON.parse(response.body)
    assert_equal 'Bad Request', json['title']
  end

  test 'create job records IP address' do
    url = 'https://github.com/rails/rails'
    Job.any_instance.expects(:parse_issues_async).once
    
    post api_v1_jobs_path, params: { url: url }, as: :json, headers: { 'REMOTE_ADDR' => '1.2.3.4' }
    
    job = Job.last
    assert_equal '1.2.3.4', job.ip
  end

  test 'show returns job details' do
    job = create(:job, url: 'https://github.com/rails/rails', status: 'pending')
    
    # Mock check_status
    Job.any_instance.expects(:check_status).once
    
    get api_v1_job_path(job), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal job.id, json['id']
    assert_equal job.url, json['url']
    assert_equal job.status, json['status']
  end

  test 'show raises not found for non-existent job' do
    get api_v1_job_path('nonexistent'), as: :json
    assert_response :not_found
  end

  test 'show calls check_status to update job' do
    job = create(:job, url: 'https://github.com/rails/rails', status: 'queued', sidekiq_id: 'fake-id')
    
    # Mock the status check
    Job.any_instance.expects(:fetch_status).returns('complete')
    
    get api_v1_job_path(job), as: :json
    assert_response :success
    
    job.reload
    assert_equal 'complete', job.status
  end
end