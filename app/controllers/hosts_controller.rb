class HostsController < ApplicationController
  before_action :find_host_by_id, only: [:show]

  def index
    @hosts = Host.all.visible.with_authors.order('repositories_count DESC')
  end

  def show
    scope = @host.repositories.visible

    sort = sanitize_sort(Repository.sortable_columns, default: 'last_synced_at')
    if params[:order] == 'asc'
      scope = scope.order(sort.asc.nulls_last)
    else
      scope = scope.order(sort.desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    fresh_when(@repositories, public: true)
  end
end
