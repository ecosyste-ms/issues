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
      
      # Move all repositories from other hosts to the target host
      hosts.each do |host|
        next if host == target_host
        
        puts "  Moving #{host.repositories.count} repositories from #{host.name} to #{target_host.name}"
        host.repositories.update_all(host_id: target_host.id)
        host.issues.update_all(host_id: target_host.id)
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
        
        if host.repositories.count == 0 && host.issues.count == 0
          puts "  Removing empty host: #{host.name}"
          host.destroy
        else
          puts "  WARNING: Host #{host.name} still has data - skipping removal"
        end
      end
    end
    
    puts "Cleanup complete."
  end
end