class Api::V1::OwnersController < Api::V1::ApplicationController
  include HostRedirect
  
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @scope = @host.repositories.where.not(owner: nil).group(:owner).count.sort_by{|k,v| -v }
    @pagy, @owners = pagy_array(@scope)
    expires_in 1.day, public: true
  end

  def show
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @owner = params[:id]

    @issues_count = @host.issues.owner(@owner).where(pull_request: false).count
    @pull_requests_count = @host.issues.owner(@owner).where(pull_request: true).count
    @merged_pull_requests_count = @host.issues.owner(@owner).where(pull_request: true).where.not(merged_at: nil).count

    @average_issue_close_time = @host.issues.owner(@owner).where(pull_request: false).average(:time_to_close)
    @average_pull_request_close_time = @host.issues.owner(@owner).where(pull_request: true).average(:time_to_close)

    @average_issue_comments_count = @host.issues.owner(@owner).where(pull_request: false).average(:comments_count)
    @average_pull_request_comments_count = @host.issues.owner(@owner).where(pull_request: true).average(:comments_count)
    
    @issue_repos = @host.issues.owner(@owner).where(pull_request: false).group(:repository).count.sort_by{|k,v| -v }
    @pull_request_repos = @host.issues.owner(@owner).where(pull_request: true).group(:repository).count.sort_by{|k,v| -v }
    
    @issue_author_associations_count = @host.issues.owner(@owner).where(pull_request: false).with_author_association.group(:author_association).count.sort_by{|k,v| -v }
    @pull_request_author_associations_count = @host.issues.owner(@owner).where(pull_request: true).with_author_association.group(:author_association).count.sort_by{|k,v| -v }

    @issue_labels_count = @host.issues.owner(@owner).where(pull_request: false).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| -v}
    @pull_request_labels_count = @host.issues.owner(@owner).where(pull_request: true).pluck(:labels).flatten.compact.group_by(&:itself).map{|k,v| [k, v.count]}.to_h.sort_by{|k,v| -v}

    @issue_authors = @host.issues.owner(@owner).where(pull_request: false).group(:user).count.sort_by{|k,v| -v }.first(15)
    @pull_request_authors = @host.issues.owner(@owner).where(pull_request: true).group(:user).count.sort_by{|k,v| -v }.first(15)

    @maintainers = @host.issues.owner(@owner).maintainers.group(:user).count.sort_by{|k,v| -v }
    @active_maintainers = @host.issues.owner(@owner).maintainers.where('issues.created_at > ?', 1.year.ago).group(:user).count.sort_by{|k,v| -v }

    expires_in 1.day, public: true
  end

  def maintainers
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened
    @owner = params[:id]

    @maintainers = @host.issues.owner(@owner).maintainers.group(:user).count.sort_by{|k,v| -v }
    @active_maintainers = @host.issues.owner(@owner).maintainers.where('issues.created_at > ?', 1.year.ago).group(:user).count.sort_by{|k,v| -v }

    expires_in 1.day, public: true    
  end
end