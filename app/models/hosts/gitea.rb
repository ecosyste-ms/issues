module Hosts
  class Gitea < Base
    IGNORABLE_EXCEPTIONS = [
      Faraday::ResourceNotFound
    ]

    def self.api_missing_error_class
      Faraday::ResourceNotFound
    end

    def icon
      'go-gitea'
    end

    def load_issues(repository)
      options = {state: 'all', order_by: 'updated_at', sort: 'desc', per_page: 100}
      options[:updated_after] = repository.last_synced_at if repository.last_synced_at.present?
      resp = api_client.get("/api/v1/repos/#{repository.full_name}/issues", options)
      return unless resp.success?

      links = parse_link_header(resp.headers)

      while links['next'].present?
        issues = resp.body
        mapped_issues = issues.map do |issue|
          {
            uuid: issue['id'],
            number: issue['number'],
            title: issue['title'],
            state: issue['state'],
            locked: issue['is_locked'],
            comments_count: issue['comments'],
            created_at: issue['created_at'],
            updated_at: issue['updated_at'],
            closed_at: issue['closed_at'],
            user: issue['user']['login'],
            labels: issue['labels'].map{|l| l['name']},
            assignees: (issue['assignees'] || []).map{|a| a['login']},
            pull_request: issue['pull_request'].present?
          }
        end
        yield mapped_issues
        resp = api_client.get(links['next'])
        links = parse_link_header(resp.headers)
      end
    end

    def api_client
      Faraday.new(@host.url, request: {timeout: 30}) do |conn|
        conn.request :authorization, :bearer, REDIS.get("gitea_token:#{@host.id}")
        conn.response :json        
      end
    end

    def parse_link_header(headers)
      return {} unless headers['Link'].present?

      links = headers['Link'].split(',').map do |link|
        url, rel = link.split(';')
        url = url[/<(.*)>/, 1]
        rel = rel[/rel="(.*)"/, 1]
        [rel, url]
      end

      Hash[links]
    end

  end
end