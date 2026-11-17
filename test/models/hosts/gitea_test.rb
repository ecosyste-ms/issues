require 'test_helper'

class Hosts::GiteaTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, kind: 'gitea', name: 'codeberg.org', url: 'https://codeberg.org')
    @repository = create(:repository, host: @host, full_name: 'owner/project')
    REDIS.stubs(:get).returns('token')
  end

  test 'sync stores a repository whose issues fit on one page' do
    stub_request(:get, %r{\Ahttps://codeberg\.org/api/v1/repos/owner/project/issues\?})
      .to_return(json([gitea_item(1, 101)]))

    @repository.sync_issues

    assert_equal [1], @repository.issues.pluck(:number)
  end

  test 'sync follows next links through the last page' do
    next_url = 'https://codeberg.org/api/v1/repos/owner/project/issues?page=2&state=all'
    stub_request(:get, %r{\Ahttps://codeberg\.org/api/v1/repos/owner/project/issues\?(?!.*page=2)})
      .to_return(json([gitea_item(1, 101)], link: "<#{next_url}>; rel=\"next\""))
    stub_request(:get, next_url)
      .to_return(json([gitea_item(2, 202, pull_request: true, closed: true)]))

    @repository.sync_issues

    assert_equal [[1, false], [2, true]], @repository.issues.order(:number).pluck(:number, :pull_request)
    assert_equal 1.day.to_i, @repository.issues.find_by(number: 2).time_to_close.to_i
  end

  test 'incremental sync asks for items updated since the last sync' do
    @repository.update!(last_synced_at: Time.zone.parse('2026-11-01 12:00:00 UTC'))
    stub_request(:get, 'https://codeberg.org/api/v1/repos/owner/project/issues')
      .with(query: { state: 'all', limit: '50', since: '2026-11-01T12:00:00Z' })
      .to_return(json([gitea_item(1, 101)]))

    @repository.sync_issues

    assert_equal [1], @repository.issues.pluck(:number)
  end

  test 'a failed page leaves the sync cursor unchanged' do
    synced_at = Time.zone.parse('2026-11-01 12:00:00 UTC')
    @repository.update!(last_synced_at: synced_at)
    next_url = 'https://codeberg.org/api/v1/repos/owner/project/issues?page=2&state=all'
    stub_request(:get, %r{\Ahttps://codeberg\.org/api/v1/repos/owner/project/issues\?(?!.*page=2)})
      .to_return(json([gitea_item(1, 101)], link: "<#{next_url}>; rel=\"next\""))
    stub_request(:get, next_url).to_return(status: 500, body: { message: 'error' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises(Faraday::Error) { @repository.sync_issues }

    assert_equal synced_at, @repository.reload.last_synced_at
    assert_equal 'error', @repository.status
  end

  test 'sync of a missing repository stores nothing' do
    stub_request(:get, %r{\Ahttps://codeberg\.org/api/v1/repos/owner/project/issues\?}).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })

    @repository.sync_issues

    assert_empty @repository.issues
  end

  def json(body, link: nil)
    headers = { 'Content-Type' => 'application/json' }
    headers['Link'] = link if link
    { status: 200, body: body.to_json, headers: headers }
  end

  def gitea_item(number, id, pull_request: false, closed: false)
    {
      id: id, number: number, title: "Item #{number}", state: closed ? 'closed' : 'open', is_locked: false, comments: 0,
      created_at: '2026-11-01T00:00:00Z', updated_at: '2026-11-02T00:00:00Z', closed_at: closed ? '2026-11-02T00:00:00Z' : nil,
      user: { login: 'author' }, labels: [], assignees: nil,
      pull_request: pull_request ? { merged: false } : nil
    }
  end
end
