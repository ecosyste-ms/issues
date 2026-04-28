require 'test_helper'

class Api::V1::RepositoriesChartDataTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_or_find_github_host
    @repository = create_repository(@host, full_name: 'charts/repo', owner: 'charts')
  end

  test 'returns chart data for issues opened' do
    create_issue(@repository, number: 1, created_at: Date.new(2026, 1, 10), user: 'alice')
    create_issue(@repository, number: 2, created_at: Date.new(2026, 1, 20), user: 'bob')
    create_issue(@repository, number: 3, created_at: Date.new(2026, 2, 1), user: 'alice')

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'issues_opened', period: 'month', start_date: '2026-01-01', end_date: '2026-02-28'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 2, data['2026-01-01']
    assert_equal 1, data['2026-02-01']
  end

  test 'returns unique issue author chart data and hides configured users' do
    hidden_user = 'secret_user'
    Owner.create!(host: @host, login: hidden_user, hidden: true)
    create_issue(@repository, number: 1, created_at: Date.new(2026, 1, 10), user: 'alice')
    create_issue(@repository, number: 2, created_at: Date.new(2026, 1, 20), user: hidden_user)

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'issue_authors', period: 'month', start_date: '2026-01-01', end_date: '2026-01-31'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data['2026-01-01']
  end

  test 'returns average pull request merge time in days' do
    create_pull_request(
      @repository,
      number: 1,
      state: 'closed',
      created_at: Date.new(2026, 1, 2),
      closed_at: Date.new(2026, 1, 4),
      merged_at: Date.new(2026, 1, 4),
      time_to_close: 3.days.to_i
    )

    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: {
      chart: 'pull_request_average_time_to_merge', period: 'month', start_date: '2026-01-01', end_date: '2026-01-31'
    }

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 3, data.values.compact.first
  end

  test 'returns bad request for unknown chart' do
    get chart_data_api_v1_host_repository_path(@host, @repository.full_name), params: { chart: 'unknown' }

    assert_response :bad_request
    assert_equal 'unknown chart', JSON.parse(response.body)['error']
  end
end
