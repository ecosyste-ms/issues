require 'test_helper'

class Repository::ReconciliationTest < ActiveSupport::TestCase
  test "enqueue schedules one full sync" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    reconciliation = repository.reconciliation
    job = mock

    reconciliation.expects(:acquire_slot).with('127.0.0.1').returns(true)
    Job.expects(:new).with(url: repository.html_url, status: 'pending', ip: '127.0.0.1').returns(job)
    job.expects(:save).returns(true)
    job.expects(:sync_issues_async).with(false, full: true).returns(true)

    assert_equal job, reconciliation.enqueue('127.0.0.1')
  end

  test "enqueue does not schedule while reconciliation is pending or fresh" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    reconciliation = repository.reconciliation

    reconciliation.expects(:acquire_slot).with('0.0.0.0').returns(false)
    Job.expects(:new).never

    assert_nil reconciliation.enqueue
  end

  test "enqueue leaves a new repository to its initial full sync" do
    host = create_or_find_github_host
    repository = create(:repository, host: host, last_synced_at: nil)
    reconciliation = repository.reconciliation

    reconciliation.expects(:acquire_slot).never
    Job.expects(:new).never

    assert_nil reconciliation.enqueue
  end

  test "admission rate limits sources and caps pending jobs" do
    host = create_or_find_github_host
    repositories = 3.times.map { create(:repository, host: host) }
    reconciliations = repositories.map(&:reconciliation)
    key_prefix = "issues:test:#{SecureRandom.hex}"
    pending_key = "#{key_prefix}:pending"
    source_keys = {
      'source-a' => "#{key_prefix}:source:a",
      'source-b' => "#{key_prefix}:source:b",
      'source-c' => "#{key_prefix}:source:c",
    }

    reconciliations.each_with_index do |reconciliation, index|
      reconciliation.stubs(:key).returns("#{key_prefix}:repository:#{index}")
      reconciliation.stubs(:pending_key).returns(pending_key)
      source_keys.each do |source, key|
        reconciliation.stubs(:source_key).with(source).returns(key)
      end
      reconciliation.stubs(:pending_ttl).returns(60)
      reconciliation.stubs(:pending_limit).returns(2)
      reconciliation.stubs(:source_interval).returns(60)
      reconciliation.stubs(:interval).returns(60)
    end

    REDIS.zadd(pending_key, 1, 'expired-repository')

    assert reconciliations[0].acquire_slot('source-a')
    assert_nil REDIS.zscore(pending_key, 'expired-repository')
    assert_not reconciliations[1].acquire_slot('source-a')
    assert reconciliations[1].acquire_slot('source-b')
    assert_not reconciliations[2].acquire_slot('source-c')
    assert_equal 2, REDIS.zcard(pending_key)

    reconciliations[0].complete

    assert reconciliations[2].acquire_slot('source-c')
    assert_equal 2, REDIS.zcard(pending_key)
  ensure
    REDIS.del(
      pending_key,
      *source_keys.values,
      *repositories.each_index.map { |index| "#{key_prefix}:repository:#{index}" }
    ) if key_prefix
  end

  test "enqueue clears its throttle when queueing fails" do
    host = create_or_find_github_host
    repository = create(:repository, host: host)
    reconciliation = repository.reconciliation
    job = mock

    reconciliation.expects(:acquire_slot).returns(true)
    reconciliation.expects(:clear).once
    Job.expects(:new).returns(job)
    job.expects(:save).returns(true)
    job.expects(:sync_issues_async).raises(StandardError.new('queue unavailable'))
    Rails.logger.expects(:error).with("Failed to enqueue reconciliation for #{repository.full_name}: queue unavailable")

    assert_nil reconciliation.enqueue
  end
end
