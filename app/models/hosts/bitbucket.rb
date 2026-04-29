module Hosts
  class Bitbucket < Base
    IGNORABLE_EXCEPTIONS = [Faraday::ResourceNotFound, Faraday::ForbiddenError, Faraday::UnauthorizedError]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'bitbucket'
    end

    def issue_url(repository, issue)
      "#{repository.host.url}/#{repository.full_name}/pull-requests/#{issue.number}"
    end

    def issues_url(repository)
      "#{url(repository)}/pull-requests"
    end

    def load_issues(repository)
      options = { state: 'ALL', pagelen: 100, sort: '-updated_on' }
      options[:q] = %(updated_on >= "#{repository.last_synced_at.iso8601}") if repository.last_synced_at.present?

      each_page("/2.0/repositories/#{repository.full_name}/pullrequests", options) do |pull_requests|
        yield pull_requests.map { |pull_request| map_pull_request(pull_request) }
      end
    rescue *IGNORABLE_EXCEPTIONS
      # Bitbucket issues are not public for many repositories; PR import is best-effort.
    end

    def map_pull_request(pull_request)
      {
        uuid: pull_request['id'],
        number: pull_request['id'],
        title: pull_request['title'],
        state: pull_request['state'].to_s.downcase,
        locked: false,
        comments_count: pull_request['comment_count'],
        created_at: pull_request['created_on'],
        updated_at: pull_request['updated_on'],
        closed_at: pull_request['state'] == 'OPEN' ? nil : pull_request['updated_on'],
        user: pull_request.dig('author', 'nickname') || pull_request.dig('author', 'display_name'),
        labels: [],
        assignees: Array(pull_request['reviewers']).map { |reviewer| reviewer['nickname'] || reviewer['display_name'] }.compact,
        pull_request: true,
        merged_at: pull_request['state'] == 'MERGED' ? pull_request['updated_on'] : nil
      }
    end

    def api_client
      Faraday.new('https://api.bitbucket.org', request: { timeout: 30 }) do |conn|
        token = REDIS.get("bitbucket_token:#{@host.id}")
        conn.request :authorization, :bearer, token if token.present?
        conn.response :json
        conn.response :raise_error
      end
    end

    def each_page(path, options = {})
      response = api_client.get(path, options)

      while response.success?
        yield Array(response.body['values'])
        next_url = response.body['next']
        break if next_url.blank?

        response = api_client.get(next_url)
      end
    end
  end
end
