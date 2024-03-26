json.login @owner
json.issues_count @issues_count
json.pull_requests_count @pull_requests_count
json.merged_pull_requests_count @merged_pull_requests_count
json.average_issue_close_time @average_issue_close_time
json.average_pull_request_close_time @average_pull_request_close_time
json.average_issue_comments_count @average_issue_comments_count
json.average_pull_request_comments_count @average_pull_request_comments_count
json.issue_repos @issue_repos do |repo, count|
  json.repository repo.full_name
  json.count count
  json.url api_v1_host_repository_url(@host, repo)
end
json.pull_request_repos @pull_request_repos do |repo, count|
  json.repository repo.full_name
  json.count count
  json.url api_v1_host_repository_url(@host, repo)
end
json.issue_author_associations_count @issue_author_associations_count do |association, count|
  json.author_association association
  json.count count
end
json.pull_request_author_associations_count @pull_request_author_associations_count do |association, count|
  json.author_association association
  json.count count
end
json.issue_labels_count @issue_labels_count do |label, count|
  json.label label
  json.count count
end
json.pull_request_labels_count @pull_request_labels_count do |label, count|
  json.label label
  json.count count
end
json.issue_authors @issue_authors do |author, count|
  json.author author
  json.count count
  json.url api_v1_host_author_url(@host, author)
end
json.pull_request_authors @pull_request_authors do |author, count|
  json.author author
  json.count count
  json.url api_v1_host_author_url(@host, author)
end