class ImportsController < ApplicationController
  def index
    @pagy, imports = pagy_countless(Import.order("filename DESC"))
    @imports = imports.sort_by { |import| import.filename.scan(/\d+|[^\d]+/).map { |s| s =~ /\d/ ? s.to_i : s } }.reverse
    @recent_stats = {
      total_recent: Import.where('created_at > ?', 24.hours.ago).count,
      successful_recent: Import.where('created_at > ?', 24.hours.ago).where(success: true).count,
      failed_recent: Import.where('created_at > ?', 24.hours.ago).where(success: false).count,
      recent_issues_count: Import.where('created_at > ?', 24.hours.ago).where(success: true).sum(:issues_count),
      recent_prs_count: Import.where('created_at > ?', 24.hours.ago).where(success: true).sum(:pull_requests_count),
      recent_created: Import.where('created_at > ?', 24.hours.ago).where(success: true).sum(:created_count),
      recent_updated: Import.where('created_at > ?', 24.hours.ago).where(success: true).sum(:updated_count)
    }
    fresh_when(@imports, public: true)
  end
end