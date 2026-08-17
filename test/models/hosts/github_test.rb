require 'test_helper'

class Hosts::GithubTest < ActiveSupport::TestCase
  setup do
    @host = create_or_find_github_host
    @repository = create(:repository, host: @host, full_name: 'owner/repository', last_synced_at: Time.zone.parse('2026-08-01 12:00:00 UTC'))
    @github = Hosts::Github.new(@host)
  end

  test 'incremental load requests issues updated since the last sync' do
    response = stub(data: [github_issue(1)], rels: {})
    expected_url = "https://api.github.com/repos/#{@repository.full_name}/issues?state=all&sort=updated&direction=desc&per_page=100&since=#{@repository.last_synced_at}"
    stub_api_request(expected_url, response)

    pages = []
    @github.load_issues(@repository) { |issues| pages << issues }

    assert_equal [[1]], pages.map { |issues| issues.map { |issue| issue[:number] } }
  end

  test 'full load omits the incremental watermark and yields every page' do
    second_response = stub(data: [github_issue(2)], rels: {})
    next_relation = mock
    next_relation.expects(:get).returns(second_response)
    first_response = stub(data: [github_issue(1)], rels: { next: next_relation })
    expected_url = "https://api.github.com/repos/#{@repository.full_name}/issues?state=all&sort=created_at&direction=asc&per_page=100"
    stub_api_request(expected_url, first_response)

    pages = []
    @github.load_issues(@repository, full: true) { |issues| pages << issues }

    assert_equal [[1], [2]], pages.map { |issues| issues.map { |issue| issue[:number] } }
  end

  def github_issue(number)
    stub(
      id: number.to_s,
      node_id: "node-#{number}",
      number: number,
      title: "Issue #{number}",
      state: 'open',
      locked: false,
      comments: 0,
      created_at: 1.day.ago,
      updated_at: Time.current,
      closed_at: nil,
      user: stub(login: 'author'),
      labels: [],
      assignees: [],
      pull_request: nil,
      author_association: 'NONE',
      state_reason: nil
    )
  end

  def stub_api_request(expected_url, response)
    agent = mock
    agent.expects(:call).with(:get, expected_url, nil, {}).returns(response)
    client = stub(api_endpoint: 'https://api.github.com/', agent: agent)
    @github.stubs(:api_client).returns(client)
  end
end
