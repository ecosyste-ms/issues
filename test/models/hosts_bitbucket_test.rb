require "test_helper"

class HostsBitbucketTest < ActiveSupport::TestCase
  setup do
    @host = Host.new(name: 'Bitbucket', url: 'https://bitbucket.org', kind: 'bitbucket')
    @repository = Repository.new(host: @host, full_name: 'workspace/project')
    @bitbucket = Hosts::Bitbucket.new(@host)
  end

  test 'issue_url points at bitbucket pull request page' do
    issue = Issue.new(number: 12, pull_request: true)

    assert_equal 'https://bitbucket.org/workspace/project/pull-requests/12', @bitbucket.issue_url(@repository, issue)
  end

  test 'map_pull_request maps bitbucket pull request payload to issue attributes' do
    payload = {
      'id' => 12,
      'title' => 'Add feature',
      'state' => 'MERGED',
      'comment_count' => 3,
      'created_on' => '2026-04-28T10:00:00Z',
      'updated_on' => '2026-04-29T10:00:00Z',
      'author' => { 'nickname' => 'alice' },
      'reviewers' => [{ 'nickname' => 'bob' }, { 'display_name' => 'Carol' }]
    }

    mapped = @bitbucket.map_pull_request(payload)

    assert_equal 12, mapped[:uuid]
    assert_equal 12, mapped[:number]
    assert_equal 'Add feature', mapped[:title]
    assert_equal 'merged', mapped[:state]
    assert_equal 3, mapped[:comments_count]
    assert_equal 'alice', mapped[:user]
    assert_equal ['bob', 'Carol'], mapped[:assignees]
    assert mapped[:pull_request]
    assert_equal '2026-04-29T10:00:00Z', mapped[:merged_at]
  end
end
