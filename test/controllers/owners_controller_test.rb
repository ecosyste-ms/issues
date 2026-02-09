require 'test_helper'

class OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_or_find_rails_repository(@host)
    @owner = @repository.owner
  end

  test 'should get index' do
    get host_owners_path(@host)
    assert_response :success
    assert_template 'owners/index'
    assert_not_nil assigns(:owners)
    assert_not_nil assigns(:pagy)
  end

  test 'should cache owners index with CDN headers' do
    get host_owners_path(@host)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 's-maxage=21600'
  end

  test 'should exclude repositories without owner' do
    # Create repository without owner
    create_repository(@host, full_name: 'orphan/repo', owner: nil)

    get host_owners_path(@host)
    assert_response :success
    
    owners = assigns(:owners)
    assert_not_nil owners
    # Should not include nil owners
    assert owners.none? { |owner, _count| owner.nil? }
  end

  test 'should order owners by repository count descending' do
    # Create repositories for different owners
    create_repository(@host, full_name: 'owner1/repo1', owner: 'owner1')
    
    # Create multiple repos for popular owner
    3.times do |i|
      create_repository(@host, 
        full_name: "popular_owner/repo#{i}",
        owner: 'popular_owner'
      )
    end

    get host_owners_path(@host)
    assert_response :success
    
    owners = assigns(:owners)
    assert_not_nil owners
    # Owners should be ordered by count descending
    assert owners.first[1] >= owners.last[1] if owners.size > 1
  end

  test 'should paginate owners' do
    # Create many owners with repositories
    30.times do |i|
      create_repository(@host,
        full_name: "owner#{i}/repo",
        owner: "owner#{i}"
      )
    end

    get host_owners_path(@host)
    assert_response :success
    
    pagy = assigns(:pagy)
    assert_not_nil pagy
    assert pagy.pages >= 1
  end

  test 'should show owner' do
    get host_owner_path(@host, @owner)
    assert_response :success
    assert_template 'owners/show'
    assert_equal @owner, assigns(:owner)
  end

  test 'should cache owner show with CDN headers' do
    get host_owner_path(@host, @owner)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 's-maxage=21600'
  end

  test 'should calculate issue statistics for owner' do
    # Create issues
    create_issue(@repository,
      number: 1001,
      state: 'closed',
      title: 'Closed issue',
      user: 'contributor1',
      pull_request: false,
      created_at: 2.days.ago,
      closed_at: 1.day.ago,
      time_to_close: 86400, # 1 day in seconds
      comments_count: 5
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    assert_not_nil assigns(:issues_count)
    assert assigns(:issues_count) >= 1
    
    assert_not_nil assigns(:average_issue_close_time)
    assert_not_nil assigns(:average_issue_comments_count)
  end

  test 'should calculate pull request statistics for owner' do
    # Create pull requests
    create_pull_request(@repository,
      number: 2001,
      state: 'closed',
      title: 'Merged PR',
      user: 'contributor2',
      created_at: 3.days.ago,
      closed_at: 1.day.ago,
      merged_at: 1.day.ago,
      time_to_close: 172800, # 2 days in seconds
      comments_count: 10
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    assert_not_nil assigns(:pull_requests_count)
    assert assigns(:pull_requests_count) >= 1
    
    assert_not_nil assigns(:merged_pull_requests_count)
    assert assigns(:merged_pull_requests_count) >= 1
    
    assert_not_nil assigns(:average_pull_request_close_time)
    assert_not_nil assigns(:average_pull_request_comments_count)
  end

  test 'should group issues by repository for owner' do
    # Create another repository for the same owner
    other_repo = create_repository(@host,
      full_name: "#{@owner}/other-repo",
      owner: @owner
    )
    
    create_issue(other_repo,
      number: 3001,
      title: 'Issue in other repo',
      user: 'contributor3',
      pull_request: false
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    issue_repos = assigns(:issue_repos)
    assert_not_nil issue_repos
    assert issue_repos.is_a?(Array)
    assert issue_repos.any? { |repo, count| count >= 1 }
  end

  test 'should group by author associations for owner' do
    # Create issues with author associations
    create_issue(@repository,
      number: 4001,
      title: 'Issue by member',
      user: 'member1',
      pull_request: false,
      author_association: 'MEMBER'
    )
    
    create_issue(@repository,
      number: 4002,
      title: 'Issue by contributor',
      user: 'contributor4',
      pull_request: false,
      author_association: 'CONTRIBUTOR'
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    associations = assigns(:issue_author_associations_count)
    assert_not_nil associations
    assert associations.is_a?(Array)
  end

  test 'should group by labels for owner' do
    # Create issues with labels
    create_issue(@repository,
      number: 5001,
      title: 'Bug issue',
      user: 'reporter1',
      pull_request: false,
      labels: ['bug', 'critical']
    )
    
    create_issue(@repository,
      number: 5002,
      title: 'Enhancement issue',
      user: 'reporter2',
      pull_request: false,
      labels: ['enhancement', 'bug']
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    labels = assigns(:issue_labels_count)
    assert_not_nil labels
    assert labels.is_a?(Array)
    assert labels.any? { |label, count| label == 'bug' && count >= 2 }
  end

  test 'should find top issue authors for owner' do
    # Create issues from different authors
    5.times do |i|
      create_issue(@repository,
        number: 6000 + i,
        title: "Issue #{i} by prolific_author",
        user: 'prolific_author',
        pull_request: false,
        created_at: i.days.ago
      )
    end

    get host_owner_path(@host, @owner)
    assert_response :success
    
    authors = assigns(:issue_authors)
    assert_not_nil authors
    assert authors.is_a?(Array)
    assert authors.size <= 15
    assert authors.first[1] >= authors.last[1] if authors.size > 1
  end

  test 'should find top pull request authors for owner' do
    # Create pull requests from different authors
    3.times do |i|
      create_pull_request(@repository,
        number: 7000 + i,
        title: "PR #{i} by active_contributor",
        user: 'active_contributor',
        created_at: i.days.ago
      )
    end

    get host_owner_path(@host, @owner)
    assert_response :success
    
    authors = assigns(:pull_request_authors)
    assert_not_nil authors
    assert authors.is_a?(Array)
    assert authors.size <= 15
  end

  test 'should find maintainers for owner' do
    # Create maintainer issues
    create_issue(@repository,
      number: 8001,
      title: 'Maintainer issue',
      user: 'maintainer1',
      author_association: 'MEMBER'
    )
    
    create_issue(@repository,
      number: 8002,
      title: 'Recent maintainer issue',
      user: 'maintainer2',
      author_association: 'OWNER',
      created_at: 1.week.ago
    )

    get host_owner_path(@host, @owner)
    assert_response :success
    
    maintainers = assigns(:maintainers)
    assert_not_nil maintainers
    assert maintainers.is_a?(Array)
    assert maintainers.size <= 15
    
    active_maintainers = assigns(:active_maintainers)
    assert_not_nil active_maintainers
    assert active_maintainers.is_a?(Array)
    assert active_maintainers.size <= 15
  end

  test 'should handle owner with no issues' do
    owner_with_no_issues = 'newowner'
    
    # Create repository for owner with no issues
    create_repository(@host,
      full_name: "#{owner_with_no_issues}/empty-repo",
      owner: owner_with_no_issues
    )
    
    get host_owner_path(@host, owner_with_no_issues)
    assert_response :success
    
    assert_equal 0, assigns(:issues_count)
    assert_equal 0, assigns(:pull_requests_count)
    assert_equal 0, assigns(:merged_pull_requests_count)
    assert_nil assigns(:average_issue_close_time)
    assert_nil assigns(:average_pull_request_close_time)
  end

  test 'should raise not found for non-existent host' do
    get host_owner_path('nonexistent', @owner)
    assert_response :not_found
  end

  test 'should redirect incorrectly cased host in owner show' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    owner = 'testowner'
    create_repository(proper_host, full_name: "#{owner}/testrepo", owner: owner)
    
    get host_owner_path('Codeberg.org', owner)
    
    assert_response :moved_permanently
    assert_redirected_to host_owner_path('codeberg.org', owner)
  end

  test 'should redirect uppercase host in owner show' do
    proper_host = create_host(name: 'gitea.com', url: 'https://gitea.com')
    owner = 'testowner'
    create_repository(proper_host, full_name: "#{owner}/testrepo", owner: owner)
    
    get host_owner_path('GITEA.COM', owner)
    
    assert_response :moved_permanently
    assert_redirected_to host_owner_path('gitea.com', owner)
  end

  test 'should redirect incorrectly cased host in owners index' do
    proper_host = create_host(name: 'codeberg.org', url: 'https://codeberg.org')
    
    get host_owners_path('Codeberg.org')
    
    assert_response :moved_permanently
    assert_redirected_to host_owners_path('codeberg.org')
  end

  test 'should show owner with exact host match without redirect' do
    proper_host = create_host(name: 'exact.host', url: 'https://exact.host')
    owner = 'testowner'
    create_repository(proper_host, full_name: "#{owner}/testrepo", owner: owner)
    
    get host_owner_path('exact.host', owner)
    
    assert_response :success
    assert_equal proper_host, assigns(:host)
    assert_equal owner, assigns(:owner)
  end
end