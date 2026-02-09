require 'test_helper'

class Api::V1::AuthorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @author = 'octocat'
    @issue = create_issue(@repository, user: @author, number: 100)
  end

  test 'index returns authors sorted by issue count' do
    # Create issues for different authors
    create_issue(@repository, user: 'author1', number: 101)
    create_issue(@repository, user: 'author2', number: 102)
    create_issue(@repository, user: 'author2', number: 103)
    create_issue(@repository, user: 'popular_author', number: 104)
    create_issue(@repository, user: 'popular_author', number: 105)
    create_issue(@repository, user: 'popular_author', number: 106)
    
    get api_v1_host_authors_path(@host), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    
    # Should be sorted by count descending
    counts = json.map { |item| item[1] }
    assert_equal counts, counts.sort.reverse
  end

  test 'index returns pagy headers' do
    # Create many authors
    30.times do |i|
      create_issue(@repository, user: "author#{i}", number: 200 + i)
    end
    
    get api_v1_host_authors_path(@host), as: :json
    assert_response :success
    
    assert response.headers['Current-Page'].present?
    assert response.headers['Total-Pages'].present?
  end

  test 'show returns author statistics' do
    # Create various issues and PRs
    create_issue(@repository, user: @author, number: 300, state: 'closed', 
                 time_to_close: 86400, comments_count: 5)
    create_pull_request(@repository, user: @author, number: 301, 
                        merged_at: 1.day.ago, time_to_close: 172800, comments_count: 10)
    
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal @author, json['login']
    assert json['issues_count'] >= 2
    assert json['pull_requests_count'] >= 1
    assert json['merged_pull_requests_count'] >= 1
    assert json.key?('average_issue_close_time')
    assert json.key?('average_pull_request_close_time')
    assert json.key?('average_issue_comments_count')
    assert json.key?('average_pull_request_comments_count')
  end

  test 'show includes repository breakdowns' do
    # Create issues in different repositories
    other_repo = create_repository(@host, full_name: 'rails/activerecord')
    create_issue(other_repo, user: @author, number: 400)
    create_pull_request(other_repo, user: @author, number: 401)
    
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_repos'].is_a?(Array)
    assert json['pull_request_repos'].is_a?(Array)
    assert json['issue_repos'].size >= 2
  end

  test 'show includes author associations' do
    # Create issues with different author associations
    create_issue(@repository, user: @author, number: 500, author_association: 'MEMBER')
    create_issue(@repository, user: @author, number: 501, author_association: 'CONTRIBUTOR')
    
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_author_associations_count'].is_a?(Array)
    assert json['pull_request_author_associations_count'].is_a?(Array)
  end

  test 'show includes label counts' do
    # Create issues with labels
    create_issue(@repository, user: @author, number: 600, labels: ['bug', 'critical'])
    create_issue(@repository, user: @author, number: 601, labels: ['enhancement'])
    create_pull_request(@repository, user: @author, number: 602, labels: ['documentation'])
    
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['issue_labels_count'].is_a?(Array)
    assert json['pull_request_labels_count'].is_a?(Array)
  end

  test 'show includes maintainers data' do
    # Create maintainer issues
    create_issue(@repository, user: 'maintainer1', number: 700, author_association: 'MEMBER')
    create_issue(@repository, user: 'maintainer2', number: 701, author_association: 'OWNER')
    
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json['maintaining'].is_a?(Array)
    assert json['active_maintaining'].is_a?(Array)
  end

  test 'show handles author with no issues' do
    author_with_no_issues = 'newauthor'
    
    get api_v1_host_author_path(@host, author_with_no_issues), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal author_with_no_issues, json['login']
    assert_equal 0, json['issues_count']
    assert_equal 0, json['pull_requests_count']
    assert_nil json['average_issue_close_time']
  end

  test 'show handles special characters in username' do
    special_author = 'user-with.dots_and-dashes'
    create_issue(@repository, user: special_author, number: 800)
    
    get api_v1_host_author_path(@host, special_author), as: :json
    assert_response :success
    
    json = JSON.parse(response.body)
    assert_equal special_author, json['login']
    assert json['issues_count'] >= 1
  end

  test 'show caches response with CDN headers' do
    get api_v1_host_author_path(@host, @author), as: :json
    assert_response :success

    assert_match(/s-maxage=3600/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end

  test 'index caches response with CDN headers' do
    get api_v1_host_authors_path(@host), as: :json
    assert_response :success

    assert_match(/s-maxage=3600/, response.headers['Cache-Control'])
    assert_match(/public/, response.headers['Cache-Control'])
  end

  test 'should redirect incorrectly cased host in API author show' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    author = 'testauthor'
    create_issue(create_repository(proper_host, full_name: 'test/repo'), user: author)
    
    get api_v1_host_author_path('Codeberg.org', author), as: :json
    
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_author_path('codeberg.org', author)
  end

  test 'should redirect incorrectly cased host in API authors index' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    
    get api_v1_host_authors_path('Codeberg.org'), as: :json
    
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_authors_path('codeberg.org')
  end
end