require 'test_helper'

class Hosts::GitlabTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, kind: 'gitlab', name: 'gitlab.com', url: 'https://gitlab.com')
    @repository = create(:repository, host: @host, full_name: 'group/project')
    REDIS.stubs(:get).returns('token')
  end

  test 'sync stores a single page of issues and every page of merge requests' do
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?})
      .to_return(json([gitlab_item(1, 101)]))
    stub_request(:get, %r{\A#{Regexp.escape(api)}/merge_requests\?(?!.*page=2)})
      .to_return(json([gitlab_item(2, 202)], link: "<#{api}/merge_requests?page=2&per_page=100&state=all>; rel=\"next\""))
    stub_request(:get, "#{api}/merge_requests?page=2&per_page=100&state=all")
      .to_return(json([gitlab_item(3, 303, closed: true)]))

    @repository.sync_issues

    assert_equal [[1, false], [2, true], [3, true]], @repository.issues.order(:number).pluck(:number, :pull_request)
    assert_equal 1.day.to_i, @repository.issues.find_by(number: 3).time_to_close.to_i
  end

  test 'a forbidden later page raises instead of ending the sync' do
    synced_at = Time.zone.parse('2026-11-01 12:00:00 UTC')
    @repository.update!(last_synced_at: synced_at)
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?(?!.*page=2)})
      .to_return(json([gitlab_item(1, 101)], link: "<#{api}/issues?page=2&per_page=100&state=all>; rel=\"next\""))
    stub_request(:get, "#{api}/issues?page=2&per_page=100&state=all")
      .to_return(status: 403, body: { message: '403 Forbidden' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(::Gitlab::Error::Forbidden) { @repository.sync_issues }

    assert_equal synced_at, @repository.reload.last_synced_at
  end

  test 'sync keeps issues when merge requests are disabled' do
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?}).to_return(json([gitlab_item(1, 101)]))
    stub_request(:get, %r{\A#{Regexp.escape(api)}/merge_requests\?})
      .to_return(status: 403, body: { message: '403 Forbidden' }.to_json, headers: { 'Content-Type' => 'application/json' })

    @repository.sync_issues

    assert_equal [1], @repository.issues.pluck(:number)
    assert_nil @repository.reload.status
  end

  test 'sync keeps merge requests when issues are disabled' do
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?})
      .to_return(status: 404, body: { message: '404 Not Found' }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{\A#{Regexp.escape(api)}/merge_requests\?}).to_return(json([gitlab_item(2, 202)]))

    @repository.sync_issues

    assert_equal [[2, true]], @repository.issues.pluck(:number, :pull_request)
  end

  test 'a server error leaves the sync cursor unchanged' do
    synced_at = Time.zone.parse('2026-11-01 12:00:00 UTC')
    @repository.update!(last_synced_at: synced_at)
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?})
      .to_return(status: 500, body: { message: '500 Internal Server Error' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(::Gitlab::Error::InternalServerError) { @repository.sync_issues }

    assert_equal synced_at, @repository.reload.last_synced_at
    assert_equal 'error', @repository.status
  end

  test 'sync stores merged merge requests as closed at their merge time' do
    api = 'https://gitlab.com/api/v4/projects/group%2Fproject'
    stub_request(:get, %r{\A#{Regexp.escape(api)}/issues\?}).to_return(json([]))
    merged = gitlab_item(2, 202).merge(state: 'merged', merged_at: '2026-11-03T00:00:00Z')
    stub_request(:get, %r{\A#{Regexp.escape(api)}/merge_requests\?}).to_return(json([merged]))

    @repository.sync_issues

    mr = @repository.issues.find_by!(number: 2)
    assert_equal Time.zone.parse('2026-11-03T00:00:00Z'), mr.merged_at
    assert_equal Time.zone.parse('2026-11-03T00:00:00Z'), mr.closed_at
    assert_equal 2.days.to_i, mr.time_to_close.to_i
  end

  def json(body, link: nil)
    headers = { 'Content-Type' => 'application/json' }
    headers['Link'] = link if link
    { status: 200, body: body.to_json, headers: headers }
  end

  def gitlab_item(iid, id, closed: false)
    {
      id: id, iid: iid, title: "Item #{iid}", state: closed ? 'closed' : 'opened', discussion_locked: false, user_notes_count: 0,
      created_at: '2026-11-01T00:00:00Z', updated_at: '2026-11-02T00:00:00Z', closed_at: closed ? '2026-11-02T00:00:00Z' : nil, merged_at: nil,
      author: { username: 'author' }, labels: [], assignees: []
    }
  end
end
