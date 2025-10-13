class GharchiveImporter
  GHARCHIVE_BASE_URL = 'https://data.gharchive.org'
  
  attr_reader :affected_repository_ids, :import_stats
  
  def initialize(host = nil)
    @host = host || Host.find_or_create_by(name: 'GitHub')
    @affected_repository_ids = Set.new
    @import_stats = { issues_count: 0, pull_requests_count: 0, created_count: 0, updated_count: 0 }
  end

  def import_hour(date, hour, update_counts: true, test_mode: false, skip_if_imported: true)
    start_time = Time.current
    Rails.logger.info "[GHArchive] Starting import for #{date} hour #{hour}"
    
    # Check if already imported
    if skip_if_imported && Import.already_imported?(date, hour)
      Rails.logger.info "[GHArchive] Skipping #{date} hour #{hour} - already imported"
      return true
    end
    
    # Reset stats for this import
    @import_stats = { issues_count: 0, pull_requests_count: 0, created_count: 0, updated_count: 0 }
    
    # Download phase
    Rails.logger.info "[GHArchive] Phase 1/4: Downloading data for #{date} hour #{hour}"
    url = build_url(date, hour)
    compressed_data = download_file(url)
    if compressed_data.nil?
      Import.record_failure(date, hour, "Failed to download file from #{url}")
      return false
    end
    Rails.logger.info "[GHArchive] Downloaded #{compressed_data.size} bytes from #{url}"
    
    # Parse phase
    Rails.logger.info "[GHArchive] Phase 2/4: Parsing JSON events"
    events = parse_jsonl(compressed_data, limit: test_mode ? 100 : nil)
    
    if test_mode && events.any? { |e| e['type'].in?(%w[IssuesEvent PullRequestEvent]) }
      # Process just a few events to test
      test_events = events.select { |e| e['type'].in?(%w[IssuesEvent PullRequestEvent]) }.first(5)
      Rails.logger.info "[GHArchive] TEST MODE: Processing #{test_events.size} test events"
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
    
    # Process phase
    Rails.logger.info "[GHArchive] Phase 3/4: Processing events and upserting data"
    process_events(events)
    
    # Update counts phase
    if update_counts && @affected_repository_ids.any?
      Rails.logger.info "[GHArchive] Phase 4/4: Updating repository and host counts for #{@affected_repository_ids.size} repositories"
      update_repository_and_host_counts
    else
      Rails.logger.info "[GHArchive] Phase 4/4: Skipping count updates (#{@affected_repository_ids.size} repositories affected)"
    end
    
    # Record successful import
    Import.create_from_import(date, hour, @import_stats)
    elapsed_time = Time.current - start_time
    Rails.logger.info "[GHArchive] Import completed for #{date} hour #{hour} in #{elapsed_time.round(2)}s: #{@import_stats}"
    
    true
  rescue => e
    Rails.logger.error "[GHArchive] Import failed for #{date} hour #{hour}: #{e.message}"
    Import.record_failure(date, hour, e.message)
    false
  end

  def import_date_range(start_date, end_date)
    range_start_time = Time.current
    total_days = (end_date - start_date).to_i + 1
    total_hours = total_days * 24
    
    Rails.logger.info "[GHArchive] Starting import for date range #{start_date} to #{end_date} (#{total_days} days, #{total_hours} hours)"
    
    completed_hours = 0
    successful_hours = 0
    failed_hours = 0
    
    (start_date..end_date).each_with_index do |date, day_index|
      Rails.logger.info "[GHArchive] Processing day #{day_index + 1}/#{total_days}: #{date}"
      
      24.times do |hour|
        # Don't update counts for each hour, do it at the end
        result = import_hour(date, hour, update_counts: false)
        completed_hours += 1
        
        if result
          successful_hours += 1
        else
          failed_hours += 1
        end
        
        if completed_hours % 24 == 0 || completed_hours == total_hours
          progress_percent = (completed_hours.to_f / total_hours * 100).round(1)
          Rails.logger.info "[GHArchive] Progress: #{completed_hours}/#{total_hours} hours (#{progress_percent}%) - #{successful_hours} successful, #{failed_hours} failed"
        end
      end
    end
    
    # Update counts once after all imports
    if @affected_repository_ids.any?
      Rails.logger.info "[GHArchive] Performing final count updates for all affected repositories"
      update_repository_and_host_counts
    end
    
    range_elapsed = Time.current - range_start_time
    Rails.logger.info "[GHArchive] Date range import completed in #{range_elapsed.round(2)}s: #{successful_hours} successful, #{failed_hours} failed out of #{total_hours} total hours"
  end

  private

  def build_url(date, hour)
    formatted_date = date.strftime('%Y-%m-%d')
    "#{GHARCHIVE_BASE_URL}/#{formatted_date}-#{hour}.json.gz"
  end

  def download_file(url)
    Rails.logger.info "[GHArchive] Downloading #{url}"

    uri = URI(url)

    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      # Ruby 3.4+ has stricter SSL defaults that check CRLs
      # Configure cert store without CRL checking to avoid issues
      cert_store = OpenSSL::X509::Store.new
      cert_store.set_default_paths
      http.cert_store = cert_store
    end

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

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
    process_start_time = Time.current
    grouped_events = events.group_by { |e| e['repo']['name'] }
    
    Rails.logger.info "[GHArchive] Processing #{events.size} events from #{grouped_events.size} repositories"
    
    # First, ensure all repositories exist by batch upserting them
    repository_names = grouped_events.keys
    repositories = batch_upsert_repositories(repository_names)
    
    # Collect all issues data for bulk upsert
    all_issues_data = []
    processed_repos = 0
    
    Rails.logger.info "[GHArchive] Processing events from each repository..."
    grouped_events.each do |repo_name, repo_events|
      repository = repositories[repo_name]
      unless repository
        Rails.logger.warn "[GHArchive] Repository #{repo_name} not found after upsert, skipping #{repo_events.size} events"
        next
      end
      
      # Track this repository as affected
      @affected_repository_ids << repository.id
      
      repo_issues = 0
      repo_prs = 0
      
      repo_events.each do |event|
        case event['type']
        when 'IssuesEvent'
          issue_data = map_issue_event(event, repository)
          if issue_data
            all_issues_data << issue_data
            repo_issues += 1
          end
        when 'PullRequestEvent'
          pr_data = map_pull_request_event(event, repository)
          if pr_data
            all_issues_data << pr_data
            repo_prs += 1
          end
        end
      end
      
      processed_repos += 1
      if processed_repos % 100 == 0 || processed_repos == grouped_events.size
        Rails.logger.info "[GHArchive] Processed #{processed_repos}/#{grouped_events.size} repositories (#{repo_name}: #{repo_issues} issues, #{repo_prs} PRs)"
      end
    end
    
    # Bulk upsert all issues at once
    if all_issues_data.any?
      Rails.logger.info "[GHArchive] Bulk upserting #{all_issues_data.size} issues across all repositories"
      bulk_upsert_issues(all_issues_data.compact)
    else
      Rails.logger.info "[GHArchive] No issues or PRs to upsert"
    end
    
    process_elapsed_time = Time.current - process_start_time
    Rails.logger.info "[GHArchive] Event processing completed in #{process_elapsed_time.round(2)}s"
  end


  def batch_upsert_repositories(repository_names)
    start_time = Time.current
    Rails.logger.info "[GHArchive] Batch upserting #{repository_names.size} repositories"
    
    # Build repository data for upsert
    repositories_data = repository_names.map do |repo_name|
      owner, name = repo_name.split('/')
      next if owner.blank? || name.blank?
      
      {
        host_id: @host.id,
        full_name: repo_name,
        owner: owner,
        created_at: Time.current,
        updated_at: Time.current
      }
    end.compact
    
    Rails.logger.info "[GHArchive] Built #{repositories_data.size} valid repository records for upsert"
    
    # Perform batch upsert
    Rails.logger.info "[GHArchive] Executing repository upsert..."
    Repository.upsert_all(
      repositories_data,
      unique_by: :index_repositories_on_host_id_lower_full_name,
      update_only: [:updated_at],
      record_timestamps: false
    )
    
    # Return hash of repo_name => repository object
    Rails.logger.info "[GHArchive] Querying for upserted repositories..."
    # Use case-insensitive lookup since the unique index is case-insensitive
    repositories = Repository.where(host: @host)
                            .where("LOWER(full_name) IN (?)", repository_names.map(&:downcase))
    
    # Build result hash with original case as keys, mapping to the found repositories
    result = {}
    repositories_by_lower_name = repositories.index_by { |r| r.full_name.downcase }
    repository_names.each do |name|
      repo = repositories_by_lower_name[name.downcase]
      result[name] = repo if repo
    end
    
    elapsed_time = Time.current - start_time
    Rails.logger.info "[GHArchive] Repository upsert completed in #{elapsed_time.round(2)}s: #{result.size} repositories ready"
    
    result
  rescue => e
    Rails.logger.error "[GHArchive] Failed to batch upsert repositories: #{e.message}"
    {}
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

    # GitHub changed the PullRequestEvent structure around Oct 9, 2025
    # New format only includes: id, number, url, base, head
    # Old format had 50+ fields including title, state, user, labels, etc.
    # We'll use whatever data is available, accepting that some fields may be nil

    created_at = pr['created_at']
    closed_at = pr['closed_at']
    merged_at = pr['merged_at']

    # Calculate time_to_close safely
    time_to_close = nil
    if closed_at.present? && created_at.present?
      begin
        time_to_close = Time.parse(closed_at.to_s) - Time.parse(created_at.to_s)
      rescue ArgumentError => e
        Rails.logger.warn "[GHArchive] Could not parse timestamps for time_to_close calculation: #{e.message}"
      end
    end

    {
      uuid: pr['id'],
      host_id: @host.id,
      repository_id: repository.id,
      number: pr['number'],
      state: pr['state'] || 'open', # Default to 'open' for new format
      title: pr['title'] || "PR ##{pr['number']}", # Default title if missing
      locked: pr['locked'] || false,
      comments_count: pr['comments'] || 0,
      user: pr['user'] ? pr['user']['login'] : nil,
      author_association: pr['author_association'],
      pull_request: true,
      created_at: created_at,
      updated_at: pr['updated_at'],
      closed_at: closed_at,
      merged_at: merged_at,
      labels: pr['labels'] ? pr['labels'].map { |l| l['name'] } : [],
      assignees: pr['assignees'] ? pr['assignees'].map { |a| a['login'] } : [],
      time_to_close: time_to_close
    }
  rescue => e
    Rails.logger.error "[GHArchive] Error mapping PR ##{pr['number']} for #{repository.full_name}: #{e.message}"
    nil
  end

  def bulk_upsert_issues(issues_data)
    return if issues_data.empty?
    
    upsert_start_time = Time.current
    Rails.logger.info "[GHArchive] Attempting to upsert #{issues_data.size} issues"
    
    # Remove duplicate uuids to avoid constraint violations
    dedup_start_time = Time.current
    issues_data = issues_data.reverse.uniq { |d| d[:uuid] }.reverse
    dedup_elapsed = Time.current - dedup_start_time
    Rails.logger.info "[GHArchive] After deduplication: #{issues_data.size} issues (took #{dedup_elapsed.round(2)}s)"
    
    # Count issues vs PRs
    issue_count = issues_data.count { |d| !d[:pull_request] }
    pr_count = issues_data.count { |d| d[:pull_request] }
    Rails.logger.info "[GHArchive] Content breakdown: #{issue_count} issues, #{pr_count} PRs"
    
    # Get existing issue UUIDs to track created vs updated (batch query)
    lookup_start_time = Time.current
    uuids = issues_data.map { |d| d[:uuid] }
    existing_uuids = Set.new(Issue.where(host_id: @host.id, uuid: uuids).pluck(:uuid).map(&:to_s))
    lookup_elapsed = Time.current - lookup_start_time
    
    created_count = issues_data.count { |d| !existing_uuids.include?(d[:uuid].to_s) }
    updated_count = issues_data.count - created_count
    Rails.logger.info "[GHArchive] Existing records lookup: #{created_count} new, #{updated_count} updates (took #{lookup_elapsed.round(2)}s)"
    
    # Process in batches to avoid memory issues with large datasets
    batch_size = 1000
    total_batches = (issues_data.size / batch_size.to_f).ceil
    Rails.logger.info "[GHArchive] Processing #{total_batches} batches of #{batch_size} issues each"
    
    issues_data.each_slice(batch_size).with_index do |batch, index|
      batch_start_time = Time.current
      Rails.logger.info "[GHArchive] Processing batch #{index + 1}/#{total_batches} (#{batch.size} issues)"
      
      Issue.upsert_all(
        batch,
        unique_by: [:host_id, :uuid],
        update_only: [:repository_id, :number, :state, :title, :locked, :comments_count, 
                      :user, :author_association, :created_at, :updated_at, :closed_at, :merged_at, 
                      :labels, :assignees, :time_to_close],
        record_timestamps: false
      )
      
      batch_elapsed = Time.current - batch_start_time
      Rails.logger.info "[GHArchive] Batch #{index + 1} completed in #{batch_elapsed.round(2)}s"
    end
    
    # Update stats
    @import_stats[:issues_count] += issue_count
    @import_stats[:pull_requests_count] += pr_count
    @import_stats[:created_count] += created_count
    @import_stats[:updated_count] += updated_count
    
    upsert_elapsed = Time.current - upsert_start_time
    Rails.logger.info "[GHArchive] Upserted #{issues_data.size} issues successfully in #{upsert_elapsed.round(2)}s (#{created_count} created, #{updated_count} updated)"
  rescue => e
    Rails.logger.error "[GHArchive] Bulk upsert failed: #{e.message}"
    Rails.logger.error "[GHArchive] Backtrace: #{e.backtrace.first(5).join("\n")}"
  end

  def update_repository_and_host_counts
    counts_start_time = Time.current
    Rails.logger.info "[GHArchive] Updating counts for #{@affected_repository_ids.size} repositories"
    
    # Update repository counts
    updated_repos = 0
    failed_repos = 0
    
    Repository.where(id: @affected_repository_ids.to_a).find_each do |repository|
      begin
        repo_start_time = Time.current
        repository.update_issue_counts
        repo_elapsed = Time.current - repo_start_time
        updated_repos += 1
        
        if updated_repos % 50 == 0 || updated_repos == @affected_repository_ids.size
          Rails.logger.info "[GHArchive] Updated counts for #{updated_repos}/#{@affected_repository_ids.size} repositories (#{repository.full_name} took #{repo_elapsed.round(2)}s)"
        end
      rescue => e
        failed_repos += 1
        Rails.logger.error "[GHArchive] Failed to update counts for repository #{repository.full_name}: #{e.message}"
      end
    end
    
    # Update host counts
    begin
      host_start_time = Time.current
      @host.update_counts
      host_elapsed = Time.current - host_start_time
      Rails.logger.info "[GHArchive] Updated counts for host #{@host.name} in #{host_elapsed.round(2)}s"
    rescue => e
      Rails.logger.error "[GHArchive] Failed to update host counts: #{e.message}"
    end
    
    # Clear the affected repositories set
    @affected_repository_ids.clear
    
    counts_elapsed = Time.current - counts_start_time
    Rails.logger.info "[GHArchive] Count updates completed in #{counts_elapsed.round(2)}s (#{updated_repos} successful, #{failed_repos} failed)"
  end
end