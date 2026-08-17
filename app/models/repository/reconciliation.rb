require 'digest'

class Repository::Reconciliation
  ADMISSION_SCRIPT = <<~LUA.freeze
    redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', ARGV[1])

    if redis.call('EXISTS', KEYS[1]) == 1 then
      return 0
    end

    if redis.call('EXISTS', KEYS[3]) == 1 then
      return 0
    end

    if redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[3]) then
      return 0
    end

    redis.call('SET', KEYS[1], 'pending', 'EX', ARGV[2])
    redis.call('SET', KEYS[3], ARGV[4], 'EX', ARGV[5])
    redis.call('ZADD', KEYS[2], tonumber(ARGV[1]) + tonumber(ARGV[2]), ARGV[4])
    redis.call('EXPIRE', KEYS[2], ARGV[2])

    return 1
  LUA

  attr_reader :repository

  def initialize(repository)
    @repository = repository
  end

  def enqueue(remote_ip = '0.0.0.0', priority = false)
    return unless repository.github?
    return if repository.last_synced_at.blank?
    return unless acquire_slot(remote_ip)

    job = Job.new(url: repository.html_url, status: 'pending', ip: remote_ip)
    unless job.save
      clear
      return
    end

    job.sync_issues_async(priority, full: true)
    job
  rescue => e
    begin
      clear
    rescue => redis_error
      Rails.logger.error "Failed to clear reconciliation throttle for #{repository.full_name}: #{redis_error.message}"
    end
    Rails.logger.error "Failed to enqueue reconciliation for #{repository.full_name}: #{e.message}"
    nil
  end

  def perform
    unless repository.github?
      raise ArgumentError, 'Full reconciliation is only supported for GitHub repositories'
    end

    repository.sync_issues(full: true)
  end

  def key
    "issues:{github-reconciliations}:repository:#{repository.id}"
  end

  def pending_key
    'issues:{github-reconciliations}:pending'
  end

  def source_key(remote_ip)
    digest = Digest::SHA256.hexdigest(remote_ip.to_s)
    "issues:{github-reconciliations}:source:#{digest}"
  end

  def pending_ttl
    1.day.to_i
  end

  def pending_limit
    ENV.fetch('GITHUB_RECONCILIATION_PENDING_LIMIT', '20').to_i.clamp(1, 100)
  end

  def source_interval
    ENV.fetch('GITHUB_RECONCILIATION_SOURCE_INTERVAL_SECONDS', '300').to_i.clamp(1, 1.day.to_i)
  end

  def interval
    ENV.fetch('GITHUB_RECONCILIATION_INTERVAL_DAYS', '30').to_i.clamp(1, 365).days.to_i
  end

  def acquire_slot(remote_ip)
    now = Time.current.to_i
    result = REDIS.eval(
      ADMISSION_SCRIPT,
      keys: [key, pending_key, source_key(remote_ip)],
      argv: [now, pending_ttl, pending_limit, repository.id, source_interval]
    )
    result == 1
  end

  def complete
    REDIS.set(key, Time.current.iso8601, ex: interval)
    release_slot
  end

  def clear
    REDIS.del(key)
    release_slot
  end

  def release_slot
    REDIS.zrem(pending_key, repository.id)
  end
end
