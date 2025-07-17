namespace :hosts do
  desc 'update counts'
  task update_counts: :environment do
    Host.all.each(&:update_counts)
  end

  desc 'sync all'
  task sync_all: :environment do
    Host.sync_all
  end

  desc 'identify duplicate hosts with different cases'
  task identify_duplicates: :environment do
    puts "Finding duplicate hosts with different cases..."
    
    hosts_by_downcase = Host.all.group_by { |host| host.name.downcase }
    duplicates = hosts_by_downcase.select { |_, hosts| hosts.length > 1 }
    
    if duplicates.empty?
      puts "No duplicate hosts found."
    else
      puts "Found #{duplicates.length} sets of duplicate hosts:"
      duplicates.each do |downcase_name, hosts|
        puts "  #{downcase_name}:"
        hosts.each do |host|
          puts "    - #{host.name} (#{host.repositories.count} repos)"
        end
      end
    end
  end

  desc 'merge repositories to downcased hosts'
  task merge_duplicates: :environment do
    puts "Merging repositories to downcased hosts..."
    
    hosts_by_downcase = Host.all.group_by { |host| host.name.downcase }
    duplicates = hosts_by_downcase.select { |_, hosts| hosts.length > 1 }
    
    duplicates.each do |downcase_name, hosts|
      puts "Processing #{downcase_name}..."
      
      # Find the target host (prefer existing downcase, otherwise downcase the first one)
      target_host = hosts.find { |h| h.name == downcase_name } || hosts.first
      
      # If no exact downcase match, update the target host name to downcase
      if target_host.name != downcase_name
        target_host.update!(name: downcase_name)
        puts "  Updated #{target_host.name} to #{downcase_name}"
      end
      
      # Move repositories from other hosts to the target host
      hosts.each do |host|
        next if host == target_host
        
        puts "  Processing #{host.repositories.count} repositories from #{host.name} to #{target_host.name}"
        
        host.repositories.find_each do |repo|
          # Check if target host already has this repository (case-insensitive)
          existing_repo = target_host.repositories.find_by('lower(full_name) = ?', repo.full_name.downcase)
          
          if existing_repo
            puts "    Repository #{repo.full_name} already exists on #{target_host.name}, merging issues..."
            # Move issues from the duplicate repo to the existing one
            repo.issues.update_all(repository_id: existing_repo.id, host_id: target_host.id)
            # Update the existing repo with the latest sync time if newer
            if repo.last_synced_at && (existing_repo.last_synced_at.nil? || repo.last_synced_at > existing_repo.last_synced_at)
              existing_repo.update!(last_synced_at: repo.last_synced_at)
            end
          else
            # No conflict, move the repository
            repo.update!(host_id: target_host.id)
            repo.issues.update_all(host_id: target_host.id)
          end
        end
      end
      
      # Update counts for the target host
      target_host.update_counts
      puts "  Updated counts for #{target_host.name}"
    end
    
    puts "Merge complete."
  end

  desc 'remove duplicate hosts after merge'
  task remove_duplicates: :environment do
    puts "Removing duplicate hosts after merge..."
    
    hosts_by_downcase = Host.all.group_by { |host| host.name.downcase }
    duplicates = hosts_by_downcase.select { |_, hosts| hosts.length > 1 }
    
    duplicates.each do |downcase_name, hosts|
      target_host = hosts.find { |h| h.name == downcase_name }
      
      hosts.each do |host|
        next if host == target_host
        
        # Clean up any remaining repositories that might be empty
        empty_repos = host.repositories.where(issues_count: 0).or(host.repositories.where(issues_count: nil))
        if empty_repos.any?
          puts "  Removing #{empty_repos.count} empty repositories from #{host.name}"
          empty_repos.destroy_all
        end
        
        if host.repositories.count == 0 && host.issues.count == 0
          puts "  Removing empty host: #{host.name}"
          host.destroy
        else
          puts "  WARNING: Host #{host.name} still has #{host.repositories.count} repositories and #{host.issues.count} issues - skipping removal"
          host.repositories.find_each do |repo|
            puts "    Repository: #{repo.full_name} (#{repo.issues.count} issues)"
          end
        end
      end
    end
    
    puts "Cleanup complete."
  end
end