class Review < ApplicationRecord
  belongs_to :repository
  belongs_to :issue, optional: true
  belongs_to :host

  scope :pull_request, ->(number) { where(pull_request_number: number) }
  scope :state, ->(state) { where(state: state) }
end
