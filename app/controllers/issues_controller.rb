class IssuesController < ApplicationController
  include HostRedirect
  
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened

    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)

    scope = @repository.issues.includes(:owner)
    hidden_users = scope.map(&:owner).compact.select(&:hidden?).map(&:login).uniq
    scope = scope.where.not(user: hidden_users) if hidden_users.any?

    @pagy, @issues = pagy(scope.order('number DESC'))
    expires_in 1.hour, public: true
  end

end