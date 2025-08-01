FactoryBot.define do
  factory :host do
    sequence(:name) { |n| "host#{n}.com" }
    url { "https://#{name}" }
    kind { 'github' }
    repositories_count { 100 }
    issues_count { 500 }
    pull_requests_count { 200 }
    authors_count { 50 }
    status { 'online' }
    online { true }
    can_crawl_api { true }
    
    trait :github do
      name { 'GitHub' }
      url { 'https://github.com' }
      kind { 'github' }
      repositories_count { 1000 }
      
      # Use find_or_create to avoid duplicates
      to_create do |instance|
        Host.find_by(name: instance.name) || instance.save!
      end
      
      after(:build) do |host|
        existing = Host.find_by(name: host.name)
        if existing
          host.id = existing.id
          host.instance_variable_set(:@new_record, false)
        end
      end
    end
    
    trait :with_no_repositories do
      repositories_count { 0 }
      issues_count { 0 }
      pull_requests_count { 0 }
      authors_count { 0 }
    end
  end
end