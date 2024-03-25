class HostsController < ApplicationController
  def index
    @hosts = Host.all.visible.order('repositories_count DESC')

    @scope = Repository.visible.order('last_synced_at DESC').includes(:host)
    @pagy, @repositories = pagy_countless(@scope, items: 10)
    fresh_when(@repositories, public: true)
  end

  def show
    @host = Host.find_by_name!(params[:id])

    scope = @host.repositories.visible

    sort = params[:sort].presence || 'last_synced_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when(@repositories, public: true)
  end
end