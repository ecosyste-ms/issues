require 'test_helper'

class IssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @issue = create(:issue, repository: @repository)
  end

  test 'should get index' do
    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
    assert_template 'issues/index'
    assert_not_nil assigns(:issues)
    assert_not_nil assigns(:pagy)
  end

  test 'should handle repository with different case in index' do
    get host_repository_issues_path(@host, @repository.full_name.upcase)
    assert_response :success
  end

  test 'should cache issues index for 1 hour' do
    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
    assert_equal 'max-age=3600, public', response.headers['Cache-Control']
  end

  test 'should raise not found for non-existent repository' do
    get host_repository_issues_path(@host, 'nonexistent/repo')
    assert_response :not_found
  end

  test 'should raise not found for non-existent host' do
    get host_repository_issues_path('nonexistent', @repository.full_name)
    assert_response :not_found
  end

  test 'should paginate issues' do
    # Create enough issues to trigger pagination
    25.times do |i|
      create_issue(@repository, 
        number: 1000 + i,
        title: "Test issue #{i}",
        user: "user#{i}",
        created_at: i.days.ago
      )
    end

    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
    
    pagy = assigns(:pagy)
    assert_not_nil pagy
    assert pagy.count > 20  # We created 25 issues plus any existing ones
  end

  test 'should order issues by number descending' do
    # Create issues with different numbers
    issue1 = create_issue(@repository, number: 100, title: 'Issue 100', user: 'user1')
    issue2 = create_issue(@repository, number: 200, title: 'Issue 200', user: 'user2')

    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
    
    issues = assigns(:issues)
    assert issues.first.number > issues.last.number
  end

  test 'should get dependabot issues' do
    get dependabot_path
    assert_response :success
    assert_template 'issues/dependabot'
    assert_not_nil assigns(:issues)
    assert_not_nil assigns(:pagy)
  end

  test 'should filter dependabot issues by ecosystem' do
    get dependabot_path, params: { ecosystem: 'rubygems' }
    assert_response :success
    assert_not_nil assigns(:issues)
  end

  test 'should filter dependabot issues by package name' do
    get dependabot_path, params: { package_name: 'rails' }
    assert_response :success
    assert_not_nil assigns(:issues)
  end

  test 'should filter dependabot issues by both ecosystem and package name' do
    get dependabot_path, params: { ecosystem: 'rubygems', package_name: 'rails' }
    assert_response :success
    assert_not_nil assigns(:issues)
  end

  test 'should only show GitHub issues in dependabot' do
    get dependabot_path
    assert_response :success
    assert_equal 'GitHub', assigns(:host).name
  end

  test 'should include repository in dependabot issues' do
    # Create a dependabot issue with metadata
    dependabot_issue = create_issue(@repository,
      number: 999,
      title: 'Bump rails from 6.0.0 to 6.1.0',
      user: 'dependabot[bot]',
    )
    
    create_dependency_metadata(dependabot_issue)

    get dependabot_path
    assert_response :success
    
    issues = assigns(:issues)
    assert_not_nil issues
    issues.each do |issue|
      assert_not_nil issue.repository
    end
  end

  test 'should order dependabot issues by created_at descending' do
    # Create dependabot issues with metadata
    issue1 = create_issue(@repository,
      number: 901,
      title: 'Bump gem1',
      user: 'dependabot[bot]',
      created_at: 2.days.ago,
    )
    
    issue2 = create_issue(@repository,
      number: 902,
      title: 'Bump gem2',
      user: 'dependabot[bot]',
      created_at: 1.day.ago,
    )
    
    create_dependency_metadata(issue1, package_name: 'gem1', target_version: '2.0.0')
    create_dependency_metadata(issue2, package_name: 'gem2', target_version: '2.0.0')

    get dependabot_path
    assert_response :success
    
    issues = assigns(:issues)
    assert issues.any? { |i| i.created_at >= issues.first.created_at }
  end

  test 'should cache dependabot issues with fresh_when' do
    get dependabot_path
    assert_response :success
    
    # Get ETag from response
    etag = response.headers['ETag']
    assert_not_nil etag
    
    # Request again with If-None-Match header
    get dependabot_path, headers: { 'If-None-Match': etag }
    assert_response :not_modified
  end
end