class IssuesController < ApplicationController
  include HostRedirect
  
  def index
    @host = find_host_with_redirect(params[:host_id])
    return if performed? # redirect already happened

    @repository = @host.repositories.find_by!('lower(full_name) = ?', params[:repository_id].downcase)

    scope = @repository.issues

    # Find hidden users efficiently without loading all issues
    hidden_users = Owner.hidden
                        .where(host_id: @host.id)
                        .where(login: scope.select(:user).distinct)
                        .pluck(:login)

    scope = scope.where.not(user: hidden_users) if hidden_users.any?

    if params[:label].presence
      @label = params[:label]
      scope = scope.label @label
    end

    @pagy, @issues = pagy(scope.order('number DESC'))
  end

end