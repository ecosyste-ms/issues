json.extract! host, :name, :url, :kind, :last_synced_at, :repositories_count, :issues_count
json.host_url api_v1_host_url(host)
json.repositories_url api_v1_host_repositories_url(host)