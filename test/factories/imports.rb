FactoryBot.define do
  factory :import do
    sequence(:filename) { |n| "import_#{n}.json" }
    imported_at { 1.day.ago }
    issues_count { 100 }
    pull_requests_count { 50 }
    created_count { 75 }
    updated_count { 75 }
    success { true }
    error_message { nil }
    
    trait :failed do
      success { false }
      error_message { "Import failed: Invalid JSON format" }
      issues_count { 0 }
      pull_requests_count { 0 }
      created_count { 0 }
      updated_count { 0 }
    end
  end
end