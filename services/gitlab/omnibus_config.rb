# GitLab CE instance configuration (gitlab.rb syntax).
#
# Loaded by the container via GITLAB_OMNIBUS_CONFIG = "from_file('/omnibus_config.rb')"
# (see services/gitlab/docker-compose.yml). Non-secret: the root password is
# supplied separately via the GITLAB_ROOT_PASSWORD env (Komodo host-local secret).
#
# GitLab serves the canonical git.phizio.net. The compose port map is 2222:22
# (host :22 is the LXC's own sshd); the cluster gitlab-ssh-lb listens on :22
# externally and forwards to the LXC's :2222.

## --- Reverse proxy + addressing ---
# The cluster Traefik terminates TLS; GitLab's nginx serves plain HTTP on :80
# inside the container (the compose publishes host 8080 -> container 80). nginx
# must NOT use 8080 — omnibus puma already binds 127.0.0.1:8080 internally.
external_url 'https://git.phizio.net'
nginx['listen_port'] = 80
nginx['listen_https'] = false

# Honour real client IPs from Traefik's X-Forwarded-For. These CIDRs (LAN
# service subnet + cluster pod/service CIDRs that NAT to the LXC) also become
# GitLab's trusted proxies.
nginx['real_ip_trusted_addresses'] = ['10.40.0.0/24', '10.244.0.0/16', '10.96.0.0/12']
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'

# git-over-SSH advertised port in clone URLs. 22 = the external port users hit
# (gitlab-ssh-lb :22 -> LXC :2222 -> container :22); compose stays 2222:22.
gitlab_rails['gitlab_shell_ssh_port'] = 22

# Container registry is handled by Harbor (registry.phizio.net), not GitLab.
registry['enable'] = false

## --- Memory tuning (official memory-constrained-environments guide) ---
puma['worker_processes'] = 2
sidekiq['concurrency'] = 10
gitlab_rails['env'] = {
  'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000'
}
gitaly['env'] = {
  'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000',
  'GITALY_COMMAND_SPAWN_MAX_PARALLEL' => '2'
}
gitaly['configuration'] = {
  concurrency: [
    { 'rpc' => '/gitaly.SmartHTTPService/PostReceivePack', 'max_per_repo' => 3 },
    { 'rpc' => '/gitaly.SSHService/SSHUploadPack', 'max_per_repo' => 3 }
  ]
}
# NB: the guide's gitaly cgroups{} block is intentionally omitted — it needs
# cgroup write delegation an unprivileged LXC + Docker does not provide.

## --- Disable bundled monitoring (~300 MB; full list from the guide) ---
prometheus_monitoring['enable'] = false
prometheus['enable'] = false
alertmanager['enable'] = false
node_exporter['enable'] = false
redis_exporter['enable'] = false
postgres_exporter['enable'] = false
gitlab_exporter['enable'] = false
sidekiq['metrics_enabled'] = false
puma['exporter_enabled'] = false
gitlab_kas['enable'] = false # no GitLab->K8s agent in use
