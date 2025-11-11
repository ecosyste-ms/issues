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

  test 'should handle issues with nil users' do
    create_issue(@repository, number: 300, title: 'Issue with nil user', user: nil)

    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
    assert_select 'p.card-subtitle', /Unknown/
  end

  test 'should handle issues with nil comments_count' do
    create_issue(@repository, number: 400, title: 'Issue with nil comments', user: 'test_user', comments_count: nil)

    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success
  end

  test 'should filter by label' do
    create_issue(@repository, number: 300, title: 'Horrible Bug', user: nil, labels: ["bug", "help wanted"])
    create_issue(@repository, number: 301, title: 'Amazing Feature', user: nil, labels: ["enhancement", "help wanted"])

    get host_repository_issues_path(@host, @repository.full_name, label: "bug")
    assert_response :success

    assert_select 'h5.card-title', /Horrible Bug/
    assert_not response.body.include? "Amazing Feature"
  end

  test 'should exclude issues from hidden owners' do
    hidden_owner = Owner.create!(login: 'hidden_user', host: @host, hidden: true)
    visible_owner = Owner.create!(login: 'visible_user', host: @host, hidden: false)

    create_issue(@repository, number: 500, title: 'Issue from hidden user', user: 'hidden_user')
    create_issue(@repository, number: 501, title: 'Issue from visible user', user: 'visible_user')

    get host_repository_issues_path(@host, @repository.full_name)
    assert_response :success

    assert_not response.body.include? "Issue from hidden user"
    assert response.body.include? "Issue from visible user"
  end

  test 'should handle large number of issues efficiently' do
    # Create a large number of issues to test performance
    200.times do |i|
      create_issue(@repository,
        number: 2000 + i,
        title: "Performance test issue #{i}",
        user: "perf_user_#{i % 10}"
      )
    end

    # This should not timeout or cause memory issues
    get host_repository_issues_path(@host, @repository.full_name, page: 2, per_page: 100)
    assert_response :success

    pagy = assigns(:pagy)
    assert_not_nil pagy
    assert pagy.count >= 200
  end

end