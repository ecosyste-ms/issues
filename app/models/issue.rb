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

  # Rows another repository's sync overwrote through a uuid collision before sync could reassign them.
  # A repository's own rows share the GitHub repository id in their node ids; rows with a different one
  # are deleted. Only a full reconciliation of their own repository restores them, as ordinary syncs
  # fetch only recently updated items.
  def self.delete_misplaced_github_rows(host, from_id: 0, batch_size: 10_000)
    max_id = maximum(:id).to_i
    deleted = 0
    home_ids = {}
    from_id.step(max_id, batch_size) do |start|
      rows = where(host_id: host.id, id: start...(start + batch_size)).where.not(node_id: nil)
        .where('EXISTS (SELECT 1 FROM issues m WHERE m.repository_id = issues.repository_id AND m.number = issues.number AND m.node_id IS NOT NULL AND m.id <> issues.id)')
        .pluck(:id, :repository_id, :node_id)
      misplaced = rows.filter_map do |id, repository_id, node_id|
        node_repository_id = github_node_repository_id(node_id)
        home_id = home_ids.fetch(repository_id) { home_ids[repository_id] = github_repository_id_for(repository_id) }
        [id, repository_id] if node_repository_id && home_id && node_repository_id != home_id
      end
      # Matching repository_id skips rows a concurrent sync has already moved to their own repository.
      deleted += misplaced.group_by(&:last).sum { |repository_id, pairs| where(id: pairs.map(&:first), repository_id: repository_id).delete_all }
      yield start + batch_size, deleted if block_given?
    end
    deleted
  end

  # The GitHub repository id at least 80% of a repository's sampled rows decode to, or nil.
  def self.github_repository_id_for(repository_id)
    # Legacy ids (MD...) carry no repository id, and older repositories are mostly legacy.
    ids = where(repository_id: repository_id).where.not(node_id: nil).where.not("node_id LIKE 'MD%'")
      .limit(100).pluck(:node_id).filter_map { |n| github_node_repository_id(n) }
    id, count = ids.tally.max_by { |_, c| c }
    id if ids.size >= 10 && count * 5 >= ids.size * 4
  end

  # New-format node ids are base64 msgpack of [0, repository id, database id]; legacy ids return nil.
  def self.github_node_repository_id(node_id)
    encoded = node_id.to_s[/\A[A-Za-z]+_([A-Za-z0-9_-]+)\z/, 1]
    return unless encoded
    bytes = Base64.urlsafe_decode64(encoded + '=' * (-encoded.length % 4)).bytes
    return unless bytes[0] == 0x93 && bytes[1] == 0x00
    case bytes[2]
    when 0x00..0x7f then bytes[2]
    when 0xcc then bytes[3]
    when 0xcd then bytes[3, 2].pack('C*').unpack1('n')
    when 0xce then bytes[3, 4].pack('C*').unpack1('N')
    end
  rescue ArgumentError
    nil
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