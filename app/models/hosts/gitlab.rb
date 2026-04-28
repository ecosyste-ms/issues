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
      
      issues = api_client.issues(repository.full_name, options)
      while issues.next_page.present?
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

        yield mapped_issues 
        issues = issues.next_page
      end

      merge_requests = api_client.merge_requests(repository.full_name, options)
      while merge_requests.next_page.present?
        mapped_merge_requests = merge_requests.map do |merge_request|
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

        yield mapped_merge_requests
        merge_requests = merge_requests.next_page
      end

    rescue IGNORABLE_EXCEPTIONS
      # merge requests may not be not enabled
    end

    def load_reviews(repository)
      repository.issues.pull_request.find_each do |merge_request|
        notes = api_client.merge_request_notes(repository.full_name, merge_request.number, per_page: 100)

        while notes.present?
          review_notes = notes.select { |note| note.system == false }
          yield review_notes.map { |note| map_review_note(note, merge_request.number) }

          break unless notes.respond_to?(:next_page) && notes.next_page.present?
          notes = notes.next_page
        end
      end
    rescue *IGNORABLE_EXCEPTIONS
      # merge requests may not be enabled
    end

    def map_review_note(note, merge_request_number)
      {
        uuid: note.id,
        node_id: nil,
        pull_request_number: merge_request_number,
        user: note.author&.username,
        state: 'COMMENTED',
        author_association: nil,
        body: note.body,
        commit_id: nil,
        submitted_at: note.created_at
      }
    end

    def api_client
      ::Gitlab.client(endpoint: "#{@host.url}/api/v4", private_token:  REDIS.get("gitlab_token:#{@host.id}"))
    end
  end
end
