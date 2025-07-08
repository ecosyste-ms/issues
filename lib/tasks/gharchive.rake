namespace :gharchive do
  desc "Show import status for recent imports"
  task status: :environment do
    puts "GHArchive Import Status"
    puts "="*50
    
    # Summary stats
    total_imports = Import.count
    successful_imports = Import.successful.count
    failed_imports = Import.failed.count
    
    puts "Total imports: #{total_imports}"
    puts "Successful: #{successful_imports}"
    puts "Failed: #{failed_imports}"
    
    # Recent imports
    puts "\nLast 10 imports:"
    puts "-"*50
    Import.recent.limit(10).each do |import|
      status = import.success? ? "✓" : "✗"
      stats = import.success? ? "(#{import.issues_count} issues, #{import.pull_requests_count} PRs)" : "(#{import.error_message})"
      puts "#{status} #{import.filename} - #{import.imported_at.strftime('%Y-%m-%d %H:%M')} #{stats}"
    end
    
    # Failed imports that can be retried
    if failed_imports > 0
      puts "\nFailed imports:"
      puts "-"*50
      Import.failed.recent.limit(10).each do |import|
        puts "#{import.filename} - #{import.error_message}"
      end
    end
  end
  desc "Import issues and pull requests from GHArchive for a specific date and hour"
  task :import_hour, [:date, :hour] => :environment do |t, args|
    date = Date.parse(args[:date])
    hour = args[:hour].to_i
    
    puts "Importing GHArchive data for #{date} hour #{hour}..."
    
    host = Host.find_or_create_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    importer.import_hour(date, hour) # This will update counts by default
    
    puts "Import completed!"
  end

  desc "Import issues and pull requests from GHArchive for an entire day"
  task :import_day, [:date] => :environment do |t, args|
    date = Date.parse(args[:date])
    
    puts "Importing GHArchive data for #{date}..."
    
    host = Host.find_or_create_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    
    # Import all hours without updating counts each time
    24.times do |hour|
      puts "Importing hour #{hour}..."
      importer.import_hour(date, hour, update_counts: false)
    end
    
    # Update counts once at the end
    puts "Import completed! Updating repository and host statistics..."
    importer.send(:update_repository_and_host_counts)
    
    puts "All statistics updated!"
  end

  desc "Import issues and pull requests from GHArchive for a date range"
  task :import_range, [:start_date, :end_date] => :environment do |t, args|
    start_date = Date.parse(args[:start_date])
    end_date = Date.parse(args[:end_date])
    
    puts "Importing GHArchive data from #{start_date} to #{end_date}..."
    
    host = Host.find_or_create_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    
    (start_date..end_date).each do |date|
      puts "\nImporting #{date}..."
      24.times do |hour|
        print "."
        importer.import_hour(date, hour)
      end
      puts " Done!"
    end
    
    puts "\nImport completed for #{(end_date - start_date).to_i + 1} days!"
  end

  desc "Import recent GHArchive data (last 24 hours)"
  task import_recent: :environment do
    # GHArchive data is typically available with a 1-2 hour delay
    end_time = Time.now.utc - 2.hours
    start_time = end_time - 24.hours
    
    puts "Importing recent GHArchive data from #{start_time} to #{end_time}..."
    
    host = Host.find_or_create_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    
    total_hours = 0
    imported_hours = 0
    skipped_hours = 0
    failed_hours = 0
    
    current_time = start_time
    while current_time < end_time
      total_hours += 1
      puts "\nImporting #{current_time.to_date} hour #{current_time.hour}..."
      
      result = importer.import_hour(current_time.to_date, current_time.hour)
      
      if result == true && Import.already_imported?(current_time.to_date, current_time.hour)
        if importer.import_stats[:created_count] == 0 && importer.import_stats[:updated_count] == 0
          skipped_hours += 1
          puts "  → Skipped (already imported)"
        else
          imported_hours += 1
          puts "  → Imported: #{importer.import_stats}"
        end
      elsif result == false
        failed_hours += 1
        puts "  → Failed!"
      end
      
      current_time += 1.hour
    end
    
    puts "\n" + "="*50
    puts "Import Summary:"
    puts "  Total hours: #{total_hours}"
    puts "  Imported: #{imported_hours}"
    puts "  Skipped: #{skipped_hours}"
    puts "  Failed: #{failed_hours}"
    puts "="*50
  end

  desc "Continuously import GHArchive data (run as a daemon)"
  task continuous_import: :environment do
    puts "Starting continuous GHArchive import..."
    
    loop do
      begin
        # Import data from 2 hours ago (to account for GHArchive delay)
        import_time = Time.now.utc - 2.hours
        
        puts "Importing GHArchive data for #{import_time}..."
        
        host = Host.find_or_create_by(name: 'GitHub')
        host.import_from_gharchive(import_time.to_date, import_time.hour)
        
        # Sleep until the next hour
        sleep_seconds = (60 - Time.now.min) * 60
        puts "Sleeping for #{sleep_seconds} seconds until next import..."
        sleep(sleep_seconds)
      rescue => e
        puts "Error during continuous import: #{e.message}"
        puts e.backtrace
        sleep(300) # Sleep 5 minutes on error
      end
    end
  end

  desc "Test GHArchive connection and parsing"
  task test: :environment do
    puts "Testing GHArchive import..."
    
    test_date = Date.today - 1
    test_hour = 12
    
    puts "Attempting to download and parse #{test_date} hour #{test_hour}..."
    
    host = Host.find_or_create_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    
    url = "https://data.gharchive.org/#{test_date.strftime('%Y-%m-%d')}-#{test_hour}.json.gz"
    puts "URL: #{url}"
    
    begin
      uri = URI(url)
      response = Net::HTTP.get_response(uri)
      
      if response.code == '200'
        puts "✓ Successfully downloaded file (#{response.body.size} bytes)"
        
        # Test parsing
        event_count = 0
        issue_event_count = 0
        pr_event_count = 0
        
        Zlib::GzipReader.new(StringIO.new(response.body)).each_line do |line|
          event = JSON.parse(line)
          event_count += 1
          
          case event['type']
          when 'IssuesEvent'
            issue_event_count += 1
            if issue_event_count == 1
              puts "\nFirst IssuesEvent:"
              puts "  Repo: #{event['repo']['name']}"
              puts "  Payload keys: #{event['payload'].keys.join(', ')}"
              puts "  Action: #{event['payload']['action']}" if event['payload']['action']
            end
          when 'PullRequestEvent'
            pr_event_count += 1
            if pr_event_count == 1
              puts "\nFirst PullRequestEvent:"
              puts "  Repo: #{event['repo']['name']}"
              puts "  Payload keys: #{event['payload'].keys.join(', ')}"
              puts "  Action: #{event['payload']['action']}" if event['payload']['action']
            end
          end
          
          break if event_count >= 1000 # Test first 1000 events
        end
        
        puts "✓ Successfully parsed events"
        puts "  Total events sampled: #{event_count}"
        puts "  Issues events: #{issue_event_count}"
        puts "  Pull request events: #{pr_event_count}"
      else
        puts "✗ Failed to download: HTTP #{response.code}"
      end
    rescue => e
      puts "✗ Error: #{e.message}"
      puts e.backtrace
    end
  end
end