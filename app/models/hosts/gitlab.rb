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

    def issue_url(repository, issue)
      "#{repository.host.url}/#{repository.full_name}/-/#{issue.pull_request ? 'merge_requests' : 'issues'}/#{issue.number}"
    end

    def load_issues(repository)
      options = {state: 'all', order_by: 'updated_at', sort: 'desc', per_page: 100}
      options[:updated_after] = repository.last_synced_at if repository.last_synced_at.present?

      each_page_if_enabled(-> { api_client.issues(repository.full_name, options) }) do |issues|
        mapped_issues = issues.map do |issue|
          {
            uuid: issue.id,
            number: issue.iid,
            title: issue.title,
            state: issue.state,
            locked: issue.discussion_locked,
            comments_count: issue.user_notes_count,
            created_at: parse_time(issue.created_at),
            updated_at: parse_time(issue.updated_at),
            closed_at: parse_time(issue.closed_at),
            user: issue.author.username,
            labels: issue.labels,
            assignees: issue.assignees.map(&:username),
            pull_request: false,
          }
        end

        yield mapped_issues
      end

      each_page_if_enabled(-> { api_client.merge_requests(repository.full_name, options) }) do |merge_requests|
        mapped_merge_requests = merge_requests.map do |merge_request|
          {
            uuid: merge_request.id,
            number: merge_request.iid,
            title: merge_request.title,
            state: merge_request.state,
            locked: merge_request.discussion_locked,
            comments_count: merge_request.user_notes_count,
            created_at: parse_time(merge_request.created_at),
            updated_at: parse_time(merge_request.updated_at),
            # GitLab leaves closed_at empty on merged MRs; GitHub sets it, and time_to_close relies on it.
            closed_at: parse_time(merge_request.closed_at || merge_request.merged_at),
            merged_at: parse_time(merge_request.merged_at),
            user: merge_request.author.username,
            labels: merge_request.labels,
            assignees: merge_request.assignees.map(&:username),
            pull_request: true,
          }
        end

        yield mapped_merge_requests
      end
    end

    # Projects can disable issues or merge requests, which fails the first request. Errors on later
    # pages raise so the sync cursor stays put.
    def each_page_if_enabled(request, &block)
      first_page = begin
        request.call
      rescue ::Gitlab::Error::NotFound, ::Gitlab::Error::Forbidden
        return
      end
      first_page.each_page(&block)
    end

    # The gem refuses to send requests without a token, but public projects don't need one.
    class AnonymousClient < ::Gitlab::Client
      def authorization_header
        {}
      end
    end

    def api_client
      token = REDIS.get("gitlab_token:#{@host.id}")
      if token.present?
        ::Gitlab.client(endpoint: "#{@host.url}/api/v4", private_token: token)
      else
        AnonymousClient.new(endpoint: "#{@host.url}/api/v4")
      end
    end
  end
end
