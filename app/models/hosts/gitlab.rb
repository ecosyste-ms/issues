module Hosts
  class Gitlab < Base
    IGNORABLE_EXCEPTIONS = [::Gitlab::Error::NotFound,
                            ::Gitlab::Error::Forbidden,
                            ::Gitlab::Error::Unauthorized,
                            ::Gitlab::Error::InternalServerError,
                            ::Gitlab::Error::Parsing]

    def self.api_missing_error_class
      ::Gitlab::Error::NotFound
    end

    def load_issues(repository)
      options = {state: 'all', order_by: 'updated_at', sort: 'desc', per_page: 100}
      options[:updated_after] = repository.last_synced_at if repository.last_synced_at.present?
      
      issues = api_client.issues(repository.full_name, options)
      mapped_issues = issues.map do |issue|
        {
          uuid: issue.id,
          number: issue.iid,
          title: issue.title,
          state: issue.state,
          locked: issue.discussion_locked,
          comments_count: issue.user_notes_count,
          created_at: issue.created_at,
          updated_at: issue.updated_at,
          closed_at: issue.closed_at,
          user: issue.author.username,
          labels: issue.labels,
          assignees: issue.assignees.map(&:username),
          pull_request: false,
        }
      end

      yield  (mapped_issues += load_merge_requests(repository))
    end

    def load_merge_requests(repository)
      options = {state: 'all', order_by: 'updated_at', sort: 'desc', per_page: 100}
      options[:updated_after] = repository.last_synced_at if repository.last_synced_at.present?

      merge_requests = api_client.merge_requests(repository.full_name, options)
      merge_requests.map do |merge_request|
        {
          uuid: merge_request.id,
          number: merge_request.iid,
          title: merge_request.title,
          state: merge_request.state,
          locked: merge_request.discussion_locked,
          comments_count: merge_request.user_notes_count,
          created_at: merge_request.created_at,
          updated_at: merge_request.updated_at,
          closed_at: merge_request.closed_at,
          user: merge_request.author.username,
          labels: merge_request.labels,
          assignees: merge_request.assignees.map(&:username),
          pull_request: true,
        }
      end
    end

    def api_client
      ::Gitlab.client(endpoint: "#{@host.url}/api/v4", private_token:  REDIS.get("gitlab_token:#{@host.id}"))
    end



  end
end
