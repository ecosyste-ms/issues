# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_07_17_151219) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "exports", force: :cascade do |t|
    t.string "date"
    t.string "bucket_name"
    t.integer "issues_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "kind"
    t.datetime "last_synced_at"
    t.integer "repositories_count"
    t.string "icon_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "issues_count"
    t.integer "pull_requests_count"
    t.integer "authors_count"
    t.index "lower((name)::text)", name: "index_hosts_on_lower_name", unique: true
  end

  create_table "imports", force: :cascade do |t|
    t.string "filename"
    t.datetime "imported_at"
    t.integer "issues_count"
    t.integer "pull_requests_count"
    t.integer "created_count"
    t.integer "updated_count"
    t.boolean "success"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["filename"], name: "index_imports_on_filename", unique: true
  end

  create_table "issues", force: :cascade do |t|
    t.integer "repository_id"
    t.string "uuid"
    t.string "node_id"
    t.integer "number"
    t.string "state"
    t.string "title"
    t.string "user"
    t.string "labels", default: [], array: true
    t.string "assignees", default: [], array: true
    t.boolean "locked"
    t.integer "comments_count"
    t.boolean "pull_request"
    t.datetime "closed_at"
    t.string "author_association"
    t.string "state_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "time_to_close"
    t.datetime "merged_at"
    t.integer "host_id"
    t.index ["host_id", "user"], name: "index_issues_on_host_id_and_user"
    t.index ["host_id", "uuid"], name: "index_issues_on_host_id_and_uuid", unique: true
    t.index ["repository_id"], name: "index_issues_on_repository_id"
  end

  create_table "jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "sidekiq_id"
    t.string "status"
    t.string "url"
    t.string "ip"
    t.json "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_jobs_on_status"
  end

  create_table "repositories", force: :cascade do |t|
    t.integer "host_id"
    t.string "full_name"
    t.string "default_branch"
    t.datetime "last_synced_at"
    t.integer "issues_count"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "pull_requests_count"
    t.float "avg_time_to_close_issue"
    t.float "avg_time_to_close_pull_request"
    t.integer "issues_closed_count"
    t.integer "pull_requests_closed_count"
    t.integer "pull_request_authors_count"
    t.integer "issue_authors_count"
    t.float "avg_comments_per_issue"
    t.float "avg_comments_per_pull_request"
    t.integer "bot_issues_count"
    t.integer "bot_pull_requests_count"
    t.integer "past_year_issues_count"
    t.integer "past_year_pull_requests_count"
    t.float "past_year_avg_time_to_close_issue"
    t.float "past_year_avg_time_to_close_pull_request"
    t.integer "past_year_issues_closed_count"
    t.integer "past_year_pull_requests_closed_count"
    t.integer "past_year_pull_request_authors_count"
    t.integer "past_year_issue_authors_count"
    t.float "past_year_avg_comments_per_issue"
    t.float "past_year_avg_comments_per_pull_request"
    t.integer "past_year_bot_issues_count"
    t.integer "past_year_bot_pull_requests_count"
    t.integer "merged_pull_requests_count"
    t.integer "past_year_merged_pull_requests_count"
    t.string "owner"
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
    t.index ["host_id", "last_synced_at"], name: "index_repositories_on_host_id_last_synced_at_null_status", where: "(status IS NULL)"
    t.index ["owner"], name: "index_repositories_on_owner"
  end
end
