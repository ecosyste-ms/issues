FactoryBot.define do
  factory :export do
    sequence(:date) { |n| (Date.today - n.days).to_s }
    sequence(:bucket_name) { |n| "bucket_#{n}" }
    issues_count { 1000 }
  end
end