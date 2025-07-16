class GharchiveImporter
  GHARCHIVE_BASE_URL = 'https://data.gharchive.org'
  
  attr_reader :affected_repository_ids, :import_stats
  
  def initialize(host = nil)
    @host = host || Host.find_or_create_by(name: 'GitHub')
    @affected_repository_ids = Set.new
    @import_stats = { issues_count: 0, pull_requests_count: 0, created_count: 0, updated_count: 0 }
  end

  def import_hour(date, hour, update_counts: true, test_mode: false, skip_if_imported: true)
    Rails.logger.info "[GHArchive] Starting import for #{date} hour #{hour}"
    
    # Check if already imported
    if skip_if_imported && Import.already_imported?(date, hour)
      Rails.logger.info "[GHArchive] Skipping #{date} hour #{hour} - already imported"
      return true
    end
    
    # Reset stats for this import
    @import_stats = { issues_count: 0, pull_requests_count: 0, created_count: 0, updated_count: 0 }
    
    url = build_url(date, hour)
    compressed_data = download_file(url)
    if compressed_data.nil?
      Import.record_failure(date, hour, "Failed to download file from #{url}")
      return false
    end
    
    events = parse_jsonl(compressed_data, limit: test_mode ? 100 : nil)
    
    if test_mode && events.any? { |e| e['type'].in?(%w[IssuesEvent PullRequestEvent]) }
      # Process just a few events to test
      test_events = events.select { |e| e['type'].in?(%w[IssuesEvent PullRequestEvent]) }.first(5)
      process_events(test_events)
      
      # Check if any issues were created
      issue_count = Issue.count
      if issue_count == 0
        Rails.logger.error "[GHArchive] TEST MODE: No issues created after processing #{test_events.size} events. Bailing out."
        Import.record_failure(date, hour, "Test mode: No issues created")
        return false
      else
        Rails.logger.info "[GHArchive] TEST MODE: Successfully created #{issue_count} issues. Continuing with full import."
      end
    end
    
    process_events(events)
    
    # Update counts for affected repositories and host
    update_repository_and_host_counts if update_counts && @affected_repository_ids.any?
    
    # Record successful import
    Import.create_from_import(date, hour, @import_stats)
    Rails.logger.info "[GHArchive] Import completed for #{date} hour #{hour}: #{@import_stats}"
    
    true
  rescue => e
    Rails.logger.error "[GHArchive] Import failed for #{date} hour #{hour}: #{e.message}"
    Import.record_failure(date, hour, e.message)
    false
  end

  def import_date_range(start_date, end_date)
    (start_date..end_date).each do |date|
      24.times do |hour|
        # Don't update counts for each hour, do it at the end
        import_hour(date, hour, update_counts: false)
      end
    end
    
    # Update counts once after all imports
    update_repository_and_host_counts if @affected_repository_ids.any?
  end

  private

  def build_url(date, hour)
    formatted_date = date.strftime('%Y-%m-%d')
    "#{GHARCHIVE_BASE_URL}/#{formatted_date}-#{hour}.json.gz"
  end

  def download_file(url)
    Rails.logger.info "[GHArchive] Downloading #{url}"
    
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    
    if response.code == '200'
      response.body
    else
      Rails.logger.error "[GHArchive] Failed to download #{url}: #{response.code}"
      nil
    end
  rescue => e
    Rails.logger.error "[GHArchive] Download error for #{url}: #{e.message}"
    nil
  end

  def parse_jsonl(compressed_data, limit: nil)
    events = []
    count = 0
    
    Zlib::GzipReader.new(StringIO.new(compressed_data)).each_line do |line|
      event = JSON.parse(line)
      
      if event['type'].in?(%w[IssuesEvent PullRequestEvent])
        events << event
        count += 1
        break if limit && count >= limit
      end
    rescue JSON::ParserError => e
      Rails.logger.warn "[GHArchive] Skipping malformed JSON: #{e.message}"
    end
    
    Rails.logger.info "[GHArchive] Parsed #{events.size} relevant events"
    events
  end

  def process_events(events)
    grouped_events = events.group_by { |e| e['repo']['name'] }
    
    Rails.logger.info "[GHArchive] Processing #{grouped_events.size} repositories"
    
    grouped_events.each do |repo_name, repo_events|
      process_repository_events(repo_name, repo_events)
    end
  end

  def process_repository_events(repo_name, events)
    repository = find_or_create_repository(repo_name)
    return unless repository
    
    # Track this repository as affected
    @affected_repository_ids << repository.id
    
    issues_data = []
    
    events.each do |event|
      case event['type']
      when 'IssuesEvent'
        issue_data = map_issue_event(event, repository)
        issues_data << issue_data if issue_data
      when 'PullRequestEvent'
        pr_data = map_pull_request_event(event, repository)
        issues_data << pr_data if pr_data
      end
    end
    
    if issues_data.any?
      Rails.logger.info "[GHArchive] Processing #{issues_data.size} issues for #{repo_name}"
      bulk_upsert_issues(issues_data.compact)
    end
  end

  def find_or_create_repository(repo_name)
    owner, name = repo_name.split('/')
    return nil unless owner && name
    
    repository = Repository.find_by(host: @host, full_name: repo_name)
    
    if repository.nil?
      repository = Repository.create!(
        host: @host,
        owner: owner,
        full_name: repo_name
      )
    end
    
    repository
  rescue => e
    Rails.logger.error "[GHArchive] Failed to find/create repository #{repo_name}: #{e.message}"
    nil
  end

  def map_issue_event(event, repository)
    issue = event['payload']['issue']
    return nil unless issue
    
    Rails.logger.debug "[GHArchive] Mapping issue ##{issue['number']} for #{repository.full_name}"
    
    created_at = issue['created_at']
    closed_at = issue['closed_at']
    
    {
      uuid: issue['id'],
      host_id: @host.id,
      repository_id: repository.id,
      number: issue['number'],
      state: issue['state'],
      title: issue['title'],
      locked: issue['locked'],
      comments_count: issue['comments'],
      user: issue['user'] ? issue['user']['login'] : nil,
      author_association: issue['author_association'],
      pull_request: false,
      created_at: created_at,
      updated_at: issue['updated_at'],
      closed_at: closed_at,
      merged_at: nil,
      labels: issue['labels'] ? issue['labels'].map { |l| l['name'] } : [],
      assignees: issue['assignees'] ? issue['assignees'].map { |a| a['login'] } : [],
      time_to_close: closed_at.present? ? Time.parse(closed_at) - Time.parse(created_at) : nil
    }
  end

  def map_pull_request_event(event, repository)
    pr = event['payload']['pull_request']
    return nil unless pr
    
    created_at = pr['created_at']
    closed_at = pr['closed_at']
    
    {
      uuid: pr['id'],
      host_id: @host.id,
      repository_id: repository.id,
      number: pr['number'],
      state: pr['state'],
      title: pr['title'],
      locked: pr['locked'],
      comments_count: pr['comments'] || 0,
      user: pr['user'] ? pr['user']['login'] : nil,
      author_association: pr['author_association'],
      pull_request: true,
      created_at: created_at,
      updated_at: pr['updated_at'],
      closed_at: closed_at,
      merged_at: pr['merged_at'],
      labels: pr['labels'] ? pr['labels'].map { |l| l['name'] } : [],
      assignees: pr['assignees'] ? pr['assignees'].map { |a| a['login'] } : [],
      time_to_close: closed_at.present? ? Time.parse(closed_at) - Time.parse(created_at) : nil
    }
  end

  def bulk_upsert_issues(issues_data)
    return if issues_data.empty?
    
    Rails.logger.info "[GHArchive] Attempting to upsert #{issues_data.size} issues"
    Rails.logger.debug "[GHArchive] First issue data: #{issues_data.first.inspect}"
    
    # Remove duplicate uuids to avoid constraint violations
    issues_data = issues_data.reverse.uniq { |d| d[:uuid] }.reverse
    
    # Count issues vs PRs
    issue_count = issues_data.count { |d| !d[:pull_request] }
    pr_count = issues_data.count { |d| d[:pull_request] }
    
    # Get existing issue UUIDs to track created vs updated
    existing_uuids = Issue.where(host_id: @host.id, uuid: issues_data.map { |d| d[:uuid] }).pluck(:uuid)
    created_count = issues_data.count { |d| !existing_uuids.include?(d[:uuid].to_s) }
    updated_count = issues_data.count - created_count
    
    result = Issue.upsert_all(
      issues_data,
      unique_by: [:host_id, :uuid],
      update_only: [:repository_id, :number, :state, :title, :locked, :comments_count, 
                    :user, :author_association, :created_at, :updated_at, :closed_at, :merged_at, 
                    :labels, :assignees, :time_to_close],
      record_timestamps: false
    )
    
    # Update stats
    @import_stats[:issues_count] += issue_count
    @import_stats[:pull_requests_count] += pr_count
    @import_stats[:created_count] += created_count
    @import_stats[:updated_count] += updated_count
    
    Rails.logger.info "[GHArchive] Upserted #{issues_data.size} issues successfully (#{created_count} created, #{updated_count} updated)"
  rescue => e
    Rails.logger.error "[GHArchive] Bulk upsert failed: #{e.message}"
    Rails.logger.error "[GHArchive] Backtrace: #{e.backtrace.first(5).join("\n")}"
  end

  def update_repository_and_host_counts
    Rails.logger.info "[GHArchive] Updating counts for #{@affected_repository_ids.size} repositories"
    
    # Update repository counts
    Repository.where(id: @affected_repository_ids.to_a).find_each do |repository|
      begin
        repository.update_issue_counts
        Rails.logger.info "[GHArchive] Updated counts for repository #{repository.full_name}"
      rescue => e
        Rails.logger.error "[GHArchive] Failed to update counts for repository #{repository.full_name}: #{e.message}"
      end
    end
    
    # Update host counts
    begin
      @host.update_counts
      Rails.logger.info "[GHArchive] Updated counts for host #{@host.name}"
    rescue => e
      Rails.logger.error "[GHArchive] Failed to update host counts: #{e.message}"
    end
    
    # Clear the affected repositories set
    @affected_repository_ids.clear
  end
end