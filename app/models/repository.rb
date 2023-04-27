class Repository < ApplicationRecord
  belongs_to :host

  validates :full_name, presence: true

  scope :active, -> { where(status: nil) }
  scope :visible, -> { active.where.not(last_synced_at: nil).where.not(total_commits: nil) }
  scope :created_after, ->(date) { where('created_at > ?', date) }
  scope :updated_after, ->(date) { where('updated_at > ?', date) }

  def self.sync_least_recently_synced
    Repository.active.order('last_synced_at ASC').limit(1000).each(&:sync_async)
  end

  def to_s
    full_name
  end

  def to_param
    full_name
  end

  def subgroups
    return [] if full_name.split('/').size < 3
    full_name.split('/')[1..-2]
  end

  def project_slug
    full_name.split('/').last
  end

  def project_name
    full_name.split('/')[1..-1].join('/')
  end

  def owner
    full_name.split('/').first
  end

  def sync_async(remote_ip = '0.0.0.0')
    job = Job.new(url: html_url, status: 'pending', ip: remote_ip)
    if job.save
      job.parse_commits_async
    end
  end

  def sync_details
    conn = Faraday.new(repos_api_url) do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    response = conn.get
    if response.status == 404
      self.status = 'not_found'
      self.save
      return
    end
    return if response.status != 200
    json = response.body

    self.status = json['status']
    self.default_branch = json['default_branch']
    self.save    
  end

  def repos_url
    "https://repos.ecosyste.ms/hosts/#{host.name}/repositories/#{full_name}"
  end

  def repos_api_url
    "https://repos.ecosyste.ms/api/v1/hosts/#{host.name}/repositories/#{full_name}"
  end

  def folder_name
    full_name.split('/').last
  end

  def html_url
    "#{host.url}/#{full_name}"
  end

  def git_clone_url
    "#{host.url}/#{full_name}.git"
  end

  def fetch_head_sha
    `git ls-remote #{git_clone_url} #{default_branch}`.split("\t").first
  end

  # TODO support hg and svn repos

  def count_commits
    sync_details
    return if status == 'not_found'
    last_commit = fetch_head_sha

    if !past_year_committers.nil? && last_synced_commit == last_commit
      update(last_synced_at: Time.now)
    else
      begin
      Dir.mktmpdir do |dir|
        `GIT_TERMINAL_PROMPT=0 git clone -b #{default_branch} --single-branch #{git_clone_url} #{dir}`
        last_commit = `git -C #{dir} rev-parse HEAD`.strip
        output = `git -C #{dir} shortlog -s -n -e --no-merges HEAD`      

        past_year_output = `git -C #{dir} shortlog -s -n -e --no-merges --since="1 year ago" HEAD`

        committers = parse_commit_counts(output)

        past_year_committers = parse_commit_counts(past_year_output)

        total_commits = committers.sum{|h| h[:count]}

        past_year_total_commits = past_year_committers.sum{|h| h[:count]}

        if past_year_committers.first
          past_year_dds = 1 - (past_year_committers.first[:count].to_f / past_year_total_commits)
          past_year_mean_commits = (past_year_total_commits.to_f / past_year_committers.length)
        else
          past_year_dds = 0
          past_year_mean_commits = 0
        end


        updates = {
          committers: committers,
          last_synced_commit: last_commit,
          total_commits: total_commits,
          total_committers: committers.length,
          mean_commits: (total_commits.to_f / committers.length),
          dds: 1 - (committers.first[:count].to_f / total_commits),
          past_year_committers: past_year_committers,
          past_year_total_commits: past_year_total_commits,
          past_year_total_committers: past_year_committers.length,
          past_year_mean_commits: past_year_mean_commits,
          past_year_dds: past_year_dds,
          last_synced_at: Time.now
        }
        update(updates)
      end
      rescue
        # TODO record error in clone (likely missing repo but also maybe host downtime)
      end
    end
    
  end

  def parse_commit_counts(output)
    # parse the output of the git command
    # return an array of hashes with the author and commit count
    lines = output.split("\n").map do |line|
      count, author = line.split("\t")
      name, email = author.split("<")
      email.gsub!(/[<>]/, '')
      { name: name.strip, email: email, count: count.to_i }
    end

    lines.group_by{|h| h[:email]}.map do |email, lines|
      { name: lines.first[:name], email: email, count: lines.sum{|h| h[:count]} }
    end.sort_by{|h| h[:count]}.reverse
  end

  def group_commits_by_email
    # temporary method to group commits by email
    return unless committers
    updated_committers = committers.group_by{|h| h["email"]}.map do |email, lines|
      { name: lines.first["name"], email: email, count: lines.sum{|h| h["count"]} }
    end

    updates = {
      committers: updated_committers,
      total_committers: updated_committers.length,
      mean_commits: (total_commits.to_f / updated_committers.length),
      dds: 1 - (updated_committers.first[:count].to_f / total_commits),
    }
    update(updates)
  end
end
