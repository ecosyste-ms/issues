require 'test_helper'

class Api::V1::OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @owner = @repository.owner
  end

  test 'index returns owners sorted by repository count' do
    # Create repositories for different owners
    create_repository(@host, full_name: 'owner1/repo1', owner: 'owner1')
    create_repository(@host, full_name: 'owner2/repo1', owner: 'owner2')
    create_repository(@host, full_name: 'owner2/repo2', owner: 'owner2')
    create_repository(@host, full_name: 'popular/repo1', owner: 'popular')
    create_repository(@host, full_name: 'popular/repo2', owner: 'popular')
    create_repository(@host, full_name: 'popular/repo3', owner: 'popular')
    
    get api_v1_host_owners_path(@host), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    
    # Should be sorted by count descending
    counts = json.map { |item| item[1] }
    assert_equal counts, counts.sort.reverse
  end

  test 'index returns owners with counts' do
    # Create some repositories for tracking
    create_repository(@host, full_name: 'test/repo1', owner: 'test')
    create_repository(@host, full_name: 'test/repo2', owner: 'test')
    
    get api_v1_host_owners_path(@host), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    # Should have some owners
    assert json.size > 0
  end

  test 'index returns pagy headers' do
    # Create many owners
    30.times do |i|
      create_repository(@host, full_name: "owner#{i}/repo", owner: "owner#{i}")
    end
    
    get api_v1_host_owners_path(@host), as: :json
    assert_response :success
    
    assert response.headers['Current-Page'].present?
    assert response.headers['Total-Pages'].present?
  end

  test 'show returns owner statistics' do
    # Create various issues and PRs
    create_issue(@repository, user: 'contributor1', number: 100, state: 'closed', 
                 time_to_close: 86400, comments_count: 5)
    create_pull_request(@repository, user: 'contributor2', number: 101, 
                        merged_at: 1.day.ago, time_to_close: 172800, comments_count: 10)
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @owner, json['login']
    assert json['issues_count'] >= 1
    assert json['pull_requests_count'] >= 1
    assert json['merged_pull_requests_count'] >= 1
    assert json.key?('average_issue_close_time')
    assert json.key?('average_pull_request_close_time')
    assert json.key?('average_issue_comments_count')
    assert json.key?('average_pull_request_comments_count')
  end

  test 'show includes repository breakdowns' do
    # Create issues in the main repository
    create_issue(@repository, user: 'contributor1', number: 100)
    create_pull_request(@repository, user: 'contributor2', number: 101)
    
    # Create another repository for the same owner
    other_repo = create_repository(@host, full_name: "#{@owner}/other-repo", owner: @owner)
    create_issue(other_repo, user: 'contributor3', number: 200)
    create_pull_request(other_repo, user: 'contributor4', number: 201)
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_repos'].is_a?(Array)
    assert json['pull_request_repos'].is_a?(Array)
    assert json['issue_repos'].size >= 2
  end

  test 'show includes author associations' do
    # Create issues with different author associations
    create_issue(@repository, user: 'member1', number: 300, author_association: 'MEMBER')
    create_issue(@repository, user: 'contributor5', number: 301, author_association: 'CONTRIBUTOR')
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_author_associations_count'].is_a?(Array)
    assert json['pull_request_author_associations_count'].is_a?(Array)
  end

  test 'show includes label counts' do
    # Create issues with labels
    create_issue(@repository, user: 'reporter1', number: 400, labels: ['bug', 'critical'])
    create_issue(@repository, user: 'reporter2', number: 401, labels: ['enhancement'])
    create_pull_request(@repository, user: 'contributor6', number: 402, labels: ['documentation'])
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_labels_count'].is_a?(Array)
    assert json['pull_request_labels_count'].is_a?(Array)
  end

  test 'show includes top authors' do
    # Create issues from different authors
    5.times do |i|
      create_issue(@repository, user: 'prolific_author', number: 500 + i)
    end
    3.times do |i|
      create_pull_request(@repository, user: 'active_contributor', number: 510 + i)
    end
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_authors'].is_a?(Array)
    assert json['pull_request_authors'].is_a?(Array)
    assert json['issue_authors'].size <= 15
    assert json['pull_request_authors'].size <= 15
  end

  test 'show includes maintainers data' do
    # Create maintainer issues
    create_issue(@repository, user: 'maintainer1', number: 600, author_association: 'MEMBER')
    create_issue(@repository, user: 'maintainer2', number: 601, author_association: 'OWNER')
    
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['maintainers'].is_a?(Array)
    assert json['active_maintainers'].is_a?(Array)
  end

  test 'show handles owner with no issues' do
    owner_with_no_issues = 'newowner'
    create_repository(@host, full_name: "#{owner_with_no_issues}/empty-repo", owner: owner_with_no_issues)
    
    get api_v1_host_owner_path(@host, owner_with_no_issues), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal owner_with_no_issues, json['login']
    assert_equal 0, json['issues_count']
    assert_equal 0, json['pull_requests_count']
    assert_nil json['average_issue_close_time']
  end

  test 'maintainers endpoint returns maintainers for owner' do
    # Create maintainer issues
    create_issue(@repository, user: 'maintainer1', number: 700, author_association: 'MEMBER')
    create_issue(@repository, user: 'maintainer2', number: 701, author_association: 'OWNER')
    create_issue(@repository, user: 'maintainer3', number: 702, author_association: 'COLLABORATOR', created_at: 2.years.ago)
    
    get maintainers_api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @owner, json['login']
    assert json['maintainers'].is_a?(Array)
    assert json['active_maintainers'].is_a?(Array)
    # Active maintainers should have fewer entries (excluding old ones)
    assert json['active_maintainers'].size <= json['maintainers'].size
  end

  test 'show caches response with CDN headers' do
    get api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success

    assert_match(/s-maxage=3600/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end

  test 'index caches response with CDN headers' do
    get api_v1_host_owners_path(@host), as: :json
    assert_response :success

    assert_match(/s-maxage=3600/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end

  test 'maintainers caches response for 1 day' do
    get maintainers_api_v1_host_owner_path(@host, @owner), as: :json
    assert_response :success
    
    # Check Cache-Control header
    assert_match(/max-age=86400/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end
end