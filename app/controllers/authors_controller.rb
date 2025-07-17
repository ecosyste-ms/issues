class AuthorsController < ApplicationController
  include HostRedirect
  
  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @author = params[:id]

    raise ActiveRecord::RecordNotFound if @host.issues.where(user: @author).empty?

    @issues_count = @host.issues.where(user: params[:id], pull_request: false).count
    @pull_requests_count = @host.issues.where(user: params[:id], pull_request: true).count
    @merged_pull_requests_count = @host.issues.where(user: params[:id], pull_request: true).where.not(merged_at: nil).count

    @average_issue_close_time = @host.issues.where(user: params[:id], pull_request: false).average(:time_to_close)
    @average_pull_request_close_time = @host.issues.where(user: params[:id], pull_request: true).average(:time_to_close)

    @average_issue_comments_count = @host.issues.where(user: params[:id], pull_request: false).average(:comments_count)
    @average_pull_request_comments_count = @host.issues.where(user: params[:id], pull_request: true).average(:comments_count)
    
    @issue_repos = @host.issues.where(user: params[:id], pull_request: false).group(:repository).count.sort_by{|k,v| -v }
    @pull_request_repos = @host.issues.where(user: params[:id], pull_request: true).group(:repository).count.sort_by{|k,v| -v }
    
    @issue_author_associations_count = @host.issues.where(user: params[:id], pull_request: false).with_author_association.group(:author_association).count.sort_by{|k,v| -v }
    @pull_request_author_associations_count = @host.issues.where(user: params[:id], pull_request: true).with_author_association.group(:author_association).count.sort_by{|k,v| -v }

    @issue_labels_count = @host.issues.where(user: params[:id]).where(pull_request: false).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| -v}
    @pull_request_labels_count = @host.issues.where(user: params[:id]).where(pull_request: true).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| -v}

    @maintainers = @host.issues.user(@author).maintainers.group(:repository).count.sort_by{|k,v| -v }.first(15)
    @active_maintainers = @host.issues.user(@author).maintainers.where('issues.created_at > ?', 1.year.ago).group(:repository).count.sort_by{|k,v| -v }.first(15)

    expires_in 1.day, public: true
  end

  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @scope = @host.issues.group(:user).count.sort_by{|k,v| -v }
    @pagy, @authors = pagy_array(@scope)
    expires_in 1.day, public: true
  end
end
