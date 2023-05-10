class Issue < ApplicationRecord
  belongs_to :repository
  belongs_to :host

  scope :past_year, -> { where('created_at > ?', 1.year.ago) }
  scope :bot, -> { where('issues.user ILIKE ?', '%[bot]') }
  scope :with_author_association, -> { where.not(author_association: nil) }
end
