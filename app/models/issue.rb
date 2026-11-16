class Issue < ApplicationRecord
  belongs_to :repository
  belongs_to :host
  belongs_to :owner, ->(issue) { where(host_id: issue.host_id) }, foreign_key: :user, primary_key: :login, optional: true

  scope :past_year, -> { where('created_at > ?', 1.year.ago) }
  scope :bot, -> { where('issues.user ILIKE ?', '%[bot]') }
  scope :human, -> { where.not('issues.user ILIKE ?', '%[bot]') }
  scope :with_author_association, -> { where.not(author_association: nil) }
  scope :merged, -> { where.not(merged_at: nil) }
  scope :not_merged, -> { where(merged_at: nil).where.not(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }
  scope :open, -> { where(closed_at: nil) }
  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :created_before, ->(date) { where('created_at < ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }
  scope :pull_request, -> { where(pull_request: true) }
  scope :issue, -> { where(pull_request: false) }

  scope :user, ->(user) { where(user: user) }
  scope :not_by, ->(logins) { logins.any? ? where('issues."user" IS NULL OR lower(issues."user") NOT IN (?)', logins.map(&:downcase)) : all }
  scope :owner, ->(owner) { joins(:repository).where('repositories.owner = ?', owner) }
  scope :maintainers, -> { where(author_association: MAINTAINER_ASSOCIATIONS) }

  scope :label, ->(label) { where('? = ANY(labels)', label) }

  def assignees_without(logins)
    hidden = logins.map(&:downcase)
    assignees.to_a.reject { |a| hidden.include?(a.to_s.downcase) }
  end

  # GH Archive PR rows (pull id uuid, no node_id) that the issues API has since synced under the issue id.
  def self.delete_gharchive_duplicates(host, from_id: 0, batch_size: 10_000)
    max_id = maximum(:id).to_i
    deleted = 0
    from_id.step(max_id, batch_size) do |start|
      deleted += where(host_id: host.id, pull_request: true, node_id: nil, id: start...(start + batch_size))
        .where('EXISTS (SELECT 1 FROM issues m WHERE m.repository_id = issues.repository_id AND m.number = issues.number AND m.pull_request AND m.node_id IS NOT NULL)')
        .delete_all
      yield start + batch_size, deleted if block_given?
    end
    deleted
  end

  def self.labels_with_counts
    from("issues, unnest(issues.labels) AS label")
      .where("label IS NOT NULL")
      .group("label")
      .order(Arel.sql("count(*) DESC"))
      .pluck(Arel.sql("label, count(*)"))
  end

  MAINTAINER_ASSOCIATIONS = ["MEMBER", "OWNER", "COLLABORATOR"]

  def to_param
    number.to_s
  end

  def html_url
    host.host_instance.issue_url(repository, self)
  end

  def bot?
    user.ends_with?('[bot]')
  end
end