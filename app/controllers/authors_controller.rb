class AuthorsController < ApplicationController
  before_action :find_host

  def show
    @author = params[:id]

    owner = Owner.find_by(host: @host, login: @author)
    raise ActiveRecord::RecordNotFound if owner&.hidden?

    author_scope = @host.issues.where(user: @author)
    raise ActiveRecord::RecordNotFound unless author_scope.exists?

    issue_scope = author_scope.where(pull_request: false)
    pr_scope = author_scope.where(pull_request: true)

    @issues_count = issue_scope.count
    @pull_requests_count = pr_scope.count
    @merged_pull_requests_count = pr_scope.where.not(merged_at: nil).count

    @average_issue_close_time = issue_scope.average(:time_to_close)
    @average_pull_request_close_time = pr_scope.average(:time_to_close)

    @average_issue_comments_count = issue_scope.average(:comments_count)
    @average_pull_request_comments_count = pr_scope.average(:comments_count)

    hidden_owners = @host.owners.hidden.pluck(:login).to_set

    @issue_repos = repos_with_counts(issue_scope, hidden_owners)
    @pull_request_repos = repos_with_counts(pr_scope, hidden_owners)

    @issue_author_associations_count = issue_scope.with_author_association.group(:author_association).count.sort_by{|k,v| -v }
    @pull_request_author_associations_count = pr_scope.with_author_association.group(:author_association).count.sort_by{|k,v| -v }

    @issue_labels_count = issue_scope.labels_with_counts
    @pull_request_labels_count = pr_scope.labels_with_counts

    @maintainers = repos_with_counts(author_scope.maintainers, hidden_owners).first(15)
    @active_maintainers = repos_with_counts(author_scope.maintainers.where('issues.created_at > ?', 1.year.ago), hidden_owners).first(15)
  end

  def repos_with_counts(scope, hidden_owners)
    rows = scope.joins(:repository)
               .group("repositories.full_name", "repositories.owner")
               .order(Arel.sql("count(*) DESC"))
               .pluck(Arel.sql("repositories.full_name, repositories.owner, count(*)"))
    rows.reject { |_name, owner, _count| hidden_owners.include?(owner) }
        .map { |name, _owner, count| [name, count] }
  end

  def index
    @scope = @host.issues.group(:user).count.sort_by{|k,v| -v }
    @pagy, @authors = pagy_array(@scope)
    @hidden_users = Owner.where(host: @host, hidden: true).pluck(:login).to_set

  end
end
