json.partial! 'api/v1/repositories/repository', repository: @repository
json.issue_labels_count @repository.issue_labels_count.to_h
json.pull_request_labels_count @repository.pull_request_labels_count.to_h

json.issue_author_associations_count @repository.issue_author_associations_count.to_h
json.pull_request_author_associations_count @repository.pull_request_author_associations_count.to_h

json.issue_authors @repository.issue_authors.to_h
json.pull_request_authors @repository.pull_request_authors.to_h
json.host @repository.host, partial: 'api/v1/hosts/host', as: :host

json.past_year_issue_labels_count @repository.past_year_issue_labels_count.to_h
json.past_year_pull_request_labels_count @repository.past_year_pull_request_labels_count.to_h

json.past_year_issue_author_associations_count @repository.past_year_issue_author_associations_count.to_h
json.past_year_pull_request_author_associations_count @repository.past_year_pull_request_author_associations_count.to_h

json.past_year_issue_authors @repository.past_year_issue_authors.to_h
json.past_year_pull_request_authors @repository.past_year_pull_request_authors.to_h
json.host @repository.host, partial: 'api/v1/hosts/host', as: :host

json.maintainers @maintainers do |maintainer, count|
  json.login maintainer
  json.count count
  json.url api_v1_host_author_url(@host, maintainer)
end

json.active_maintainers @active_maintainers do |maintainer, count|
  json.login maintainer
  json.count count
  json.url api_v1_host_author_url(@host, maintainer)
end