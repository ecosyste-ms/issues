class ExportsController < ApplicationController
  def index
    @exports = Export.order("date DESC")
    fresh_when(@exports, public: true)
  end
end