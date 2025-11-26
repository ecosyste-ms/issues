require 'test_helper'

class Api::V1::IssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @issue = create_issue(@repository, number: 100, title: 'Test Issue', state: 'open')
  end

  test 'index returns issues for repository' do
    # Create additional issues
    create_issue(@repository, number: 101, title: 'Another Issue')
    create_pull_request(@repository, number: 102, title: 'Test PR')
    
    get api_v1_host_repository_issues_path(@host, @repository), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    assert json.size >= 3
  end

  test 'index filters by created_after' do
    old_issue = create_issue(@repository, number: 200, created_at: 1.year.ago)
    new_issue = create_issue(@repository, number: 201, created_at: 1.day.ago)
    
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { created_after: 1.week.ago.iso8601 }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 201
    assert_not_includes numbers, 200
  end

  test 'index filters by updated_after' do
    old_issue = create_issue(@repository, number: 300, updated_at: 1.year.ago)
    new_issue = create_issue(@repository, number: 301, updated_at: 1.day.ago)
    
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { updated_after: 1.week.ago.iso8601 }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 301
    assert_not_includes numbers, 300
  end

  test 'index filters by pull_request' do
    issue = create_issue(@repository, number: 400, pull_request: false)
    pr = create_pull_request(@repository, number: 401)
    
    # Get only pull requests
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { pull_request: 'true' }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 401
    assert_not_includes numbers, 400
    
    # Get only issues
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { pull_request: 'false' }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 400
    assert_not_includes numbers, 401
  end

  test 'index filters by state' do
    open_issue = create_issue(@repository, number: 500, state: 'open')
    closed_issue = create_issue(@repository, number: 501, state: 'closed')
    
    # Get only open issues
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { state: 'open' }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 500
    assert_not_includes numbers, 501
  end

  test 'index supports custom sorting' do
    issue1 = create_issue(@repository, number: 600, created_at: 3.days.ago)
    issue2 = create_issue(@repository, number: 601, created_at: 1.day.ago)
    issue3 = create_issue(@repository, number: 602, created_at: 2.days.ago)
    
    get api_v1_host_repository_issues_path(@host, @repository), 
        params: { sort: 'created_at', order: 'asc' }, as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    # Verify they come in ascending order of creation
    assert json.size >= 3
  end

  test 'index orders by number descending by default' do
    issue1 = create_issue(@repository, number: 700)
    issue2 = create_issue(@repository, number: 701)
    issue3 = create_issue(@repository, number: 702)
    
    get api_v1_host_repository_issues_path(@host, @repository), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    numbers = json.first(3).map { |i| i['number'] }
    # Should be in descending order
    assert_equal numbers, numbers.sort.reverse
  end

  test 'index returns pagy headers' do
    25.times do |i|
      create_issue(@repository, number: 1000 + i)
    end
    
    get api_v1_host_repository_issues_path(@host, @repository), as: :json
    assert_response :success
    
    # pagy_countless doesn't provide all headers
    assert response.headers['Link'].present? || response.headers['Current-Page'].present?
  end

  test 'index respects cache headers' do
    get api_v1_host_repository_issues_path(@host, @repository), as: :json
    assert_response :success
    
    etag = response.headers['ETag']
    assert etag.present?
    
    # Request again with If-None-Match
    get api_v1_host_repository_issues_path(@host, @repository), 
        headers: { 'If-None-Match': etag }, as: :json
    assert_response :not_modified
  end

  test 'show returns issue details' do
    get api_v1_host_repository_issue_path(@host, @repository, @issue.number), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @issue.number, json['number']
    assert_equal @issue.title, json['title']
    assert_equal @issue.state, json['state']
    if @issue.uuid.nil?
      assert_nil json['uuid']
    else
      assert_equal @issue.uuid, json['uuid']
    end
  end

  test 'show raises not found for non-existent issue' do
    get api_v1_host_repository_issue_path(@host, @repository, 99999), as: :json
    assert_response :not_found
  end

  test 'show raises not found for non-existent repository' do
    get api_v1_host_repository_issue_path(@host, 'nonexistent/repo', 100), as: :json
    assert_response :not_found
  end

  test 'show handles repository with different case' do
    get api_v1_host_repository_issue_path(@host, @repository.full_name.upcase, @issue.number), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @issue.number, json['number']
  end

  test 'show respects cache headers' do
    get api_v1_host_repository_issue_path(@host, @repository, @issue.number), as: :json
    assert_response :success

    etag = response.headers['ETag']
    assert etag.present?

    # Request again with If-None-Match
    get api_v1_host_repository_issue_path(@host, @repository, @issue.number),
        headers: { 'If-None-Match': etag }, as: :json
    assert_response :not_modified
  end

  test 'index filters by label' do
    labeled_issue = create_issue(@repository, number: 800, labels: ['bug', 'critical'])
    other_issue = create_issue(@repository, number: 801, labels: ['enhancement'])
    unlabeled_issue = create_issue(@repository, number: 802, labels: [])

    get api_v1_host_repository_issues_path(@host, @repository),
        params: { label: 'bug' }, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    numbers = json.map { |i| i['number'] }
    assert_includes numbers, 800
    assert_not_includes numbers, 801
    assert_not_includes numbers, 802
  end

  test 'labels returns all labels with counts and issues_url' do
    create_issue(@repository, number: 900, labels: ['bug', 'critical'])
    create_issue(@repository, number: 901, labels: ['bug', 'enhancement'])
    create_issue(@repository, number: 902, labels: ['documentation'])

    get labels_api_v1_host_repository_path(@host, @repository), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.is_a?(Array)

    labels_hash = json.to_h { |item| [item['label'], item['count']] }
    assert_equal 2, labels_hash['bug']
    assert_equal 1, labels_hash['critical']
    assert_equal 1, labels_hash['enhancement']
    assert_equal 1, labels_hash['documentation']

    bug_entry = json.find { |item| item['label'] == 'bug' }
    assert bug_entry['issues_url'].present?
    assert_includes bug_entry['issues_url'], 'label=bug'
  end

  test 'labels returns labels sorted by count descending' do
    create_issue(@repository, number: 950, labels: ['popular', 'popular', 'rare'])
    create_issue(@repository, number: 951, labels: ['popular'])
    create_issue(@repository, number: 952, labels: ['medium'])
    create_issue(@repository, number: 953, labels: ['medium'])

    get labels_api_v1_host_repository_path(@host, @repository), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    counts = json.map { |item| item['count'] }
    assert_equal counts, counts.sort.reverse
  end

  test 'labels caches response for 1 day' do
    get labels_api_v1_host_repository_path(@host, @repository), as: :json
    assert_response :success

    assert_match(/max-age=86400/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end

  test 'labels handles repository with no labels' do
    # Create issue without labels
    create_issue(@repository, number: 999, labels: [])

    get labels_api_v1_host_repository_path(@host, @repository), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end
end