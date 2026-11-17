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

    def issue_url(repository, issue)
      repository.html_url + "/#{issue.pull_request ? 'pulls' : 'issues'}/#{issue.number}"
    end

    def load_issues(repository)
      options = {state: 'all', limit: 50}
      options[:since] = repository.last_synced_at.iso8601 if repository.last_synced_at.present?
      resp = api_client.get("/api/v1/repos/#{repository.full_name}/issues", options)
      return if resp.status == 404
      raise_unless_success(resp)

      loop do
        issues = resp.body
        mapped_issues = issues.map do |issue|
          {
            uuid: issue['id'],
            number: issue['number'],
            title: issue['title'],
            state: issue['state'],
            locked: issue['is_locked'],
            comments_count: issue['comments'],
            created_at: parse_time(issue['created_at']),
            updated_at: parse_time(issue['updated_at']),
            closed_at: parse_time(issue['closed_at']),
            user: issue['user']['login'],
            labels: issue['labels'].map{|l| l['name']},
            assignees: (issue['assignees'] || []).map{|a| a['login']},
            pull_request: issue['pull_request'].present?
          }
        end
        yield mapped_issues
        next_url = parse_link_header(resp.headers)['next']
        break unless next_url.present?
        resp = api_client.get(next_url)
        raise_unless_success(resp)
      end
    end

    # Raising keeps the sync cursor where it was, so the next sync refetches what this one missed.
    def raise_unless_success(resp)
      raise Faraday::Error, "Gitea API returned #{resp.status} for #{resp.env.url}" unless resp.success?
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