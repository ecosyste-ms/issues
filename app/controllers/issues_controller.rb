class IssuesController < ApplicationController
  before_action :find_host

  def index
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
