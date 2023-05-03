module Hosts
  class Github < Base
    IGNORABLE_EXCEPTIONS = [
      Octokit::Unauthorized,
      Octokit::InvalidRepository,
      # Octokit::RepositoryUnavailable,
      # Octokit::NotFound,
      Octokit::Conflict,
      # Octokit::Forbidden,
      Octokit::InternalServerError,
      Octokit::BadGateway,
      # Octokit::UnavailableForLegalReasons
      Octokit::SAMLProtected
    ]

    def self.api_missing_error_class
      [
        Octokit::NotFound,
        Octokit::RepositoryUnavailable,
        Octokit::UnavailableForLegalReasons
      ]
    end

    def icon
      'github'
    end

    def token_set_key
      "github_tokens"
    end

    def list_tokens
      REDIS.smembers(token_set_key)
    end

    def fetch_random_token
      REDIS.srandmember(token_set_key)
    end

    def add_tokens(tokens)
      REDIS.sadd(token_set_key, tokens)
    end

    def remove_token(token)
      REDIS.srem(token_set_key, token)
    end

    def check_tokens
      list_tokens.each do |token|
        begin
          api_client(token).rate_limit!
        rescue Octokit::Unauthorized, Octokit::AccountSuspended
          puts "Removing token #{token}"
          remove_token(token)
        end
      end
    end

    def html_url(repository)
      "https://github.com/#{repository.full_name}"
    end

    def load_issues(repository)
      issues = api_client.issues(repository.full_name, state: 'all')
      issues.map do |issue|
        {
          uuid: issue.id,
          node_id: issue.node_id,
          number: issue.number,
          title: issue.title,
          state: issue.state,
          locked: issue.locked,
          comments_count: issue.comments,
          created_at: issue.created_at,
          updated_at: issue.updated_at,
          closed_at: issue.closed_at,
          body: issue.body,
          user: issue.user.login,
          labels: issue.labels.map(&:name),
          assignees: issue.assignees.map(&:login),
          pull_request: issue.pull_request.present?,
          closed_by: issue.closed_by.try(:login),
          author_association: issue.author_association,
          state_reason: issue.state_reason
        }
      end
    end

    def events_for_repo(full_name, event_type: nil, per_page: 100)
      url = "https://timeline.ecosyste.ms/api/v1/events/#{full_name}?per_page=#{per_page}"
      url = "#{url}&event_type=#{event_type}" if event_type.present?

      begin
        resp = Faraday.get(url) do |req|
          req.options.timeout = 5
        end

        if resp.success?
          Oj.load(resp.body)
        else
          {}
        end
      rescue Faraday::Error
        {}
      end
    end

    def attempt_load_from_timeline(full_name)
      events = events_for_repo(full_name, event_type: 'PullRequestEvent', per_page: 1)
      return nil if events.blank?
      events.first['payload']['pull_request']['base']['repo'].to_hash.with_indifferent_access
    rescue
      nil
    end

    private

    def api_client(token = nil, options = {})
      token = fetch_random_token if token.nil?
      Octokit::Client.new({access_token: token, auto_paginate: true}.merge(options))
    end
  end
end
