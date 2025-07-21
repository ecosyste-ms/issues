class HomeController < ApplicationController
  def index
    @hosts = Host.visible.order('repositories_count DESC')

    @repositories = Repository.visible.order('last_synced_at DESC').includes(:host).limit(10)
  end
end