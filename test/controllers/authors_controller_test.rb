require 'test_helper'

class AuthorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @author = 'octocat'
    @issue = create(:issue, user: @author, repository: create(:repository, host: @host))
  end

  test 'should get index' do
    get host_authors_path(@host)
    assert_response :success
    assert_template 'authors/index'
    assert_not_nil assigns(:authors)
    assert_not_nil assigns(:pagy)
  end

  test 'should cache authors index for 1 day' do
    get host_authors_path(@host)
    assert_response :success
    assert_equal 'max-age=86400, public', response.headers['Cache-Control']
  end

  test 'should order authors by issue count descending' do
    # Create issues for different authors
    create_issue(@issue.repository, number: 101, user: 'author1')
    
    5.times do |i|
      create_issue(@issue.repository, 
        number: 200 + i,
        title: "Issue #{i} by popular_author",
        user: 'popular_author',
        created_at: i.days.ago
      )
    end

    get host_authors_path(@host)
    assert_response :success
    
    authors = assigns(:authors)
    assert_not_nil authors
    # Authors should be ordered by count descending
    assert authors.first[1] >= authors.last[1] if authors.size > 1
  end

  test 'should paginate authors' do
    # Create many authors with issues
    30.times do |i|
      create_issue(@issue.repository,
        number: 300 + i,
        title: "Issue by author#{i}",
        user: "author#{i}",
        created_at: i.days.ago
      )
    end

    get host_authors_path(@host)
    assert_response :success
    
    pagy = assigns(:pagy)
    assert_not_nil pagy
    assert pagy.pages >= 1
  end

  test 'should show author' do
    get host_author_path(@host, @author)
    assert_response :success
    assert_template 'authors/show'
    assert_equal @author, assigns(:author)
  end

  test 'should cache author show for 1 day' do
    get host_author_path(@host, @author)
    assert_response :success
    assert_equal 'max-age=86400, public', response.headers['Cache-Control']
  end

  test 'should calculate issue statistics' do
    # Create issues
    create_issue(@issue.repository,
      number: 401,
      state: 'closed',
      title: 'Closed issue',
      user: @author,
      pull_request: false,
      created_at: 2.days.ago,
      closed_at: 1.day.ago,
      time_to_close: 86400, # 1 day in seconds
      comments_count: 5
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    assert_not_nil assigns(:issues_count)
    assert assigns(:issues_count) >= 1
    
    assert_not_nil assigns(:average_issue_close_time)
    assert_not_nil assigns(:average_issue_comments_count)
  end

  test 'should calculate pull request statistics' do
    # Create pull requests
    create_pull_request(@issue.repository,
      number: 501,
      state: 'closed',
      title: 'Merged PR',
      user: @author,
      created_at: 3.days.ago,
      closed_at: 1.day.ago,
      merged_at: 1.day.ago,
      time_to_close: 172800, # 2 days in seconds
      comments_count: 10
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    assert_not_nil assigns(:pull_requests_count)
    assert assigns(:pull_requests_count) >= 1
    
    assert_not_nil assigns(:merged_pull_requests_count)
    assert assigns(:merged_pull_requests_count) >= 1
    
    assert_not_nil assigns(:average_pull_request_close_time)
    assert_not_nil assigns(:average_pull_request_comments_count)
  end

  test 'should group issues by repository' do
    # Create issues in different repositories
    other_repo = create_repository(@host,
      full_name: 'rails/activerecord',
      owner: 'rails'
    )
    
    create_issue(other_repo,
      number: 601,
      title: 'Issue in other repo',
      user: @author,
      pull_request: false
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    issue_repos = assigns(:issue_repos)
    assert_not_nil issue_repos
    assert issue_repos.is_a?(Array)
    assert issue_repos.any? { |repo, count| count >= 1 }
  end

  test 'should group by author associations' do
    # Create issues with author associations
    create_issue(@issue.repository,
      number: 701,
      title: 'Issue as member',
      user: @author,
      pull_request: false,
      author_association: 'MEMBER'
    )
    
    create_issue(@issue.repository,
      number: 702,
      title: 'Issue as contributor',
      user: @author,
      pull_request: false,
      author_association: 'CONTRIBUTOR'
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    associations = assigns(:issue_author_associations_count)
    assert_not_nil associations
    assert associations.is_a?(Array)
  end

  test 'should group by labels' do
    # Create issues with labels
    create_issue(@issue.repository,
      number: 801,
      title: 'Bug issue',
      user: @author,
      pull_request: false,
      labels: ['bug', 'critical']
    )
    
    create_issue(@issue.repository,
      number: 802,
      title: 'Enhancement issue',
      user: @author,
      pull_request: false,
      labels: ['enhancement', 'bug']
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    labels = assigns(:issue_labels_count)
    assert_not_nil labels
    assert labels.is_a?(Array)
    assert labels.any? { |label, count| label == 'bug' && count >= 2 }
  end

  test 'should find maintainers who worked on same repositories' do
    # Create maintainer issues
    create_issue(@issue.repository,
      number: 901,
      title: 'Maintainer issue',
      user: 'maintainer1',
      author_association: 'MEMBER'
    )

    get host_author_path(@host, @author)
    assert_response :success
    
    maintainers = assigns(:maintainers)
    assert_not_nil maintainers
    assert maintainers.is_a?(Array)
    
    active_maintainers = assigns(:active_maintainers)
    assert_not_nil active_maintainers
    assert active_maintainers.is_a?(Array)
  end

  test 'should return 404 for author with no issues' do
    author_with_no_issues = 'newauthor'
    
    get host_author_path(@host, author_with_no_issues)
    assert_response :not_found
  end

  test 'should raise not found for non-existent host' do
    get host_author_path('nonexistent', @author)
    assert_response :not_found
  end

  test 'should redirect incorrectly cased host in author show' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    author = 'testauthor'
    create_issue(create_repository(proper_host, full_name: 'test/repo'), user: author)
    
    get host_author_path('Codeberg.org', author)
    
    assert_response :moved_permanently
    assert_redirected_to host_author_path('codeberg.org', author)
  end

  test 'should redirect uppercase host in author show' do
    proper_host = create_host(name: 'gitea.com', url: 'https://gitea.com')
    author = 'testauthor'
    create_issue(create_repository(proper_host, full_name: 'test/repo'), user: author)
    
    get host_author_path('GITEA.COM', author)
    
    assert_response :moved_permanently
    assert_redirected_to host_author_path('gitea.com', author)
  end

  test 'should redirect incorrectly cased host in authors index' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    
    get host_authors_path('Codeberg.org')
    
    assert_response :moved_permanently
    assert_redirected_to host_authors_path('codeberg.org')
  end

  test 'should show author with exact host match without redirect' do
    proper_host = create_host(name: 'exact.host', url: 'https://exact.host')
    author = 'testauthor'
    create_issue(create_repository(proper_host, full_name: 'test/repo'), user: author)

    get host_author_path('exact.host', author)

    assert_response :success
    assert_equal proper_host, assigns(:host)
    assert_equal author, assigns(:author)
  end

  test 'should return 404 for hidden author' do
    hidden_author = 'hidden_user'
    Owner.create!(host: @host, login: hidden_author, hidden: true)
    create_issue(@issue.repository, number: 999, user: hidden_author)

    get host_author_path(@host, hidden_author)
    assert_response :not_found
  end

  test 'should set hidden users for view filtering' do
    # Create a hidden author
    hidden_author = 'hidden_user'
    Owner.create!(host: @host, login: hidden_author, hidden: true)

    # Create issues for both visible and hidden authors
    create_issue(@issue.repository, number: 1001, user: 'visible_author')
    create_issue(@issue.repository, number: 1002, user: hidden_author)

    get host_authors_path(@host)
    assert_response :success

    hidden_users = assigns(:hidden_users)
    assert_not_nil hidden_users
    assert hidden_users.include?(hidden_author)
  end

  test 'should handle multiple hidden authors in index' do
    # Create multiple hidden authors
    hidden1 = 'hidden_user1'
    hidden2 = 'hidden_user2'
    Owner.create!(host: @host, login: hidden1, hidden: true)
    Owner.create!(host: @host, login: hidden2, hidden: true)

    # Create issues
    create_issue(@issue.repository, number: 1101, user: hidden1)
    create_issue(@issue.repository, number: 1102, user: hidden2)
    create_issue(@issue.repository, number: 1103, user: 'visible_user')

    get host_authors_path(@host)
    assert_response :success

    hidden_users = assigns(:hidden_users)
    assert_not_nil hidden_users
    assert hidden_users.include?(hidden1)
    assert hidden_users.include?(hidden2)
  end

  test 'should hide repos with hidden owners on author show page' do
    # Create hidden owner
    hidden_owner = 'hidden_owner'
    Owner.create!(host: @host, login: hidden_owner, hidden: true)

    # Create repos with visible and hidden owners
    visible_repo = create_repository(@host, full_name: 'visible_owner/repo1', owner: 'visible_owner')
    hidden_repo = create_repository(@host, full_name: 'hidden_owner/repo2', owner: hidden_owner)

    # Create issues in both repos by the author
    create_issue(visible_repo, number: 2001, user: @author, pull_request: false)
    create_issue(hidden_repo, number: 2002, user: @author, pull_request: false)

    get host_author_path(@host, @author)
    assert_response :success

    issue_repos = assigns(:issue_repos)
    assert_not_nil issue_repos

    # Visible repo should be present
    assert issue_repos.any? { |full_name, _count| full_name == 'visible_owner/repo1' }

    # Hidden repo should NOT be present
    assert_not issue_repos.any? { |full_name, _count| full_name == 'hidden_owner/repo2' }
  end

  test 'should hide pull request repos with hidden owners on author show page' do
    # Create hidden owner
    hidden_owner = 'hidden_pr_owner'
    Owner.create!(host: @host, login: hidden_owner, hidden: true)

    # Create repos with visible and hidden owners
    visible_repo = create_repository(@host, full_name: 'visible_pr_owner/repo1', owner: 'visible_pr_owner')
    hidden_repo = create_repository(@host, full_name: 'hidden_pr_owner/repo2', owner: hidden_owner)

    # Create pull requests in both repos by the author
    create_pull_request(visible_repo, number: 3001, user: @author)
    create_pull_request(hidden_repo, number: 3002, user: @author)

    get host_author_path(@host, @author)
    assert_response :success

    pr_repos = assigns(:pull_request_repos)
    assert_not_nil pr_repos

    # Visible repo should be present
    assert pr_repos.any? { |full_name, _count| full_name == 'visible_pr_owner/repo1' }

    # Hidden repo should NOT be present
    assert_not pr_repos.any? { |full_name, _count| full_name == 'hidden_pr_owner/repo2' }
  end

  test 'should hide maintainer repos with hidden owners on author show page' do
    # Create hidden owner
    hidden_owner = 'hidden_maintainer_owner'
    Owner.create!(host: @host, login: hidden_owner, hidden: true)

    # Create repos
    visible_repo = create_repository(@host, full_name: 'visible_maint_owner/repo1', owner: 'visible_maint_owner')
    hidden_repo = create_repository(@host, full_name: 'hidden_maintainer_owner/repo2', owner: hidden_owner)

    # Create issues where @author is a maintainer (MEMBER association)
    create_issue(visible_repo, number: 4001, user: @author, author_association: 'MEMBER')
    create_issue(hidden_repo, number: 4002, user: @author, author_association: 'MEMBER')

    get host_author_path(@host, @author)
    assert_response :success

    maintainers = assigns(:maintainers)
    assert_not_nil maintainers

    # Visible repo should be present
    assert maintainers.any? { |full_name, _count| full_name == 'visible_maint_owner/repo1' }

    # Hidden repo should NOT be present
    assert_not maintainers.any? { |full_name, _count| full_name == 'hidden_maintainer_owner/repo2' }
  end

  test 'should hide active maintainer repos with hidden owners on author show page' do
    # Create hidden owner
    hidden_owner = 'hidden_active_owner'
    Owner.create!(host: @host, login: hidden_owner, hidden: true)

    # Create repos
    visible_repo = create_repository(@host, full_name: 'visible_active_owner/repo1', owner: 'visible_active_owner')
    hidden_repo = create_repository(@host, full_name: 'hidden_active_owner/repo2', owner: hidden_owner)

    # Create recent issues where @author is a maintainer (MEMBER association)
    create_issue(visible_repo, number: 5001, user: @author, author_association: 'MEMBER', created_at: 1.month.ago)
    create_issue(hidden_repo, number: 5002, user: @author, author_association: 'MEMBER', created_at: 1.month.ago)

    get host_author_path(@host, @author)
    assert_response :success

    active_maintainers = assigns(:active_maintainers)
    assert_not_nil active_maintainers

    # Visible repo should be present
    assert active_maintainers.any? { |full_name, _count| full_name == 'visible_active_owner/repo1' }

    # Hidden repo should NOT be present
    assert_not active_maintainers.any? { |full_name, _count| full_name == 'hidden_active_owner/repo2' }
  end
end