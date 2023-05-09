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
      url = "#{api_client.api_endpoint}repos/#{repository.full_name}/issues?state=all&sort=updated&direction=desc&per_page=100"
      url = "#{url}&since=#{repository.last_synced_at}" if repository.last_synced_at.present?

      response = api_client.agent.call(:get, url, nil, {})
      
      mapped_issues = map_issues(response.data)

      yield(mapped_issues)

      while response && response.rels[:next]
        response = response.rels[:next].get

        map_issues(response.data)

        yield(mapped_issues)
      end 
    end

    def map_issues(data)
      data.map do |issue|
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
          user: issue.user.login,
          labels: issue.labels.map(&:name),
          assignees: issue.assignees.map(&:login),
          pull_request: issue.pull_request.present?,
          author_association: issue.author_association,
          state_reason: issue.state_reason,
          merged_at: issue.pull_request.present? ? issue.pull_request.merged_at : nil,
        }
      end
    end

    private

    def api_client(token = nil, options = {})
      token = fetch_random_token if token.nil?
      Octokit::Client.new({access_token: token, auto_paginate: true}.merge(options))
    end
  end
end
