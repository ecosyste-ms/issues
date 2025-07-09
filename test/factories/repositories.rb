FactoryBot.define do
  factory :repository do
    association :host
    sequence(:full_name) { |n| "owner#{n}/repo#{n}" }
    owner { full_name.split('/').first }
    default_branch { 'main' }
    last_synced_at { 1.hour.ago }
    issues_count { 10 }
    pull_requests_count { 5 }
    status { nil }
    
    trait :rails do
      full_name { 'rails/rails' }
      owner { 'rails' }
      issues_count { 100 }
      pull_requests_count { 50 }
      
      # Use find_or_create to avoid duplicates
      to_create do |instance|
        Repository.find_by(host_id: instance.host_id, full_name: instance.full_name) || instance.save!
      end
      
      after(:build) do |repository|
        existing = Repository.find_by(host_id: repository.host_id, full_name: repository.full_name)
        if existing
          repository.id = existing.id
          repository.instance_variable_set(:@new_record, false)
        end
      end
    end
    
    trait :not_synced do
      last_synced_at { nil }
    end
    
    trait :recently_synced do
      last_synced_at { 5.minutes.ago }
    end
    
    trait :old_sync do
      last_synced_at { 2.days.ago }
    end
    
    trait :with_error do
      status { 'error' }
    end
  end
end