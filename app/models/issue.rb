class Issue < ApplicationRecord
  belongs_to :repository
  belongs_to :host

  scope :past_year, -> { where('created_at > ?', 1.year.ago) }
  scope :bot, -> { where('issues.user ILIKE ?', '%[bot]') }
  scope :with_author_association, -> { where.not(author_association: nil) }
  scope :merged, -> { where.not(merged_at: nil) }

  DEPENDABOT_USERNAMES = ['dependabot[bot]', 'dependabot-preview[bot]'].freeze
  DEPENDABOT_ECOSYSTEMS = {
    'ruby' => 'rubygems',
    'docker' => 'docker',
    'rust' => 'cargo',
    'github_actions' => 'actions',
    'javascript' => 'npm',
    'go' => 'go',
    'php' => 'packagist',
    'python' => 'pip',
    'elixir' => 'hex',
    '.NET' => 'nuget',
    'npm' => 'npm',
    'yarn' => 'npm',
    'java' => 'maven',
    'elm' => 'elm',
    'gomod' => 'go',
    'terraform' => 'terraform',
    'gradle' => 'gradle',
    'pip' => 'pip',
    'dart' => 'pub',
  }

  scope :dependabot, -> { where(user: DEPENDABOT_USERNAMES) }
  scope :with_dependency_metadata, -> { where('length(dependency_metadata::text) > 2') }
  scope :package_name, ->(package_name) { dependabot.with_dependency_metadata.where("dependency_metadata->>'package_name' = ?", package_name) }
  scope :ecosystem, ->(ecosystem) { dependabot.with_dependency_metadata.where("dependency_metadata->>'ecosystem' = ?", ecosystem) }

  def html_url
    host.host_instance.issue_url(repository, self)
  end

  def parse_dependabot_metadata
    return unless user.in?(DEPENDABOT_USERNAMES)
    ecosystem = DEPENDABOT_ECOSYSTEMS.keys & labels.map(&:downcase)
    match = title.match(/^(?<prefix>.+?) (?<package_name>\S+) from (?<old_version>\S+) to (?<new_version>\S+)(?: (?<path>.+))?$/)
    
    return unless match
    {
      prefix: match[:prefix],
      package_name: match[:package_name],
      old_version: match[:old_version],
      new_version: match[:new_version],
      path: match[:path],
      ecosystem: DEPENDABOT_ECOSYSTEMS[ecosystem.first],
    }
  end

  def update_dependabot_metadata
    metadata = parse_dependabot_metadata
    update(dependency_metadata: metadata) if metadata.present?
  end
end