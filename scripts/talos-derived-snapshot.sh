#!/usr/bin/env bash
# Snapshot what Talos derives from the machine config, per node, so two
# snapshots can be diffed to prove a config change is a no-op in effect.
#
# `talosctl apply-config --dry-run` diffs the config documents, which says
# nothing when a change only moves settings between documents. These
# resources are what the controllers actually render: static pod specs,
# kubelet and component configs, bootstrap manifests, node labels/taints,
# kernel settings, resolvers, time servers. Secret resources are excluded.
#
# Usage: scripts/talos-derived-snapshot.sh <out-dir> [node-ip...]
#   default nodes: all control planes and workers
#   compare:       diff -r <before-dir> <after-dir>
#
# Needs talosctl and yq; reads TALOSCONFIG (default:
# ansible/talos/configs/talosconfig) and uses the VIP as endpoint.

set -euo pipefail

OUT="${1:-}"
[[ -n "${OUT}" ]] || {
    echo "Usage: $0 <out-dir> [node-ip...]" >&2
    exit 1
}
shift
NODES=("$@")
((${#NODES[@]})) || NODES=(10.140.0.41 10.140.0.42 10.140.0.43 10.140.0.51 10.140.0.52 10.140.0.53)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TALOSCONFIG="${TALOSCONFIG:-${REPO_ROOT}/ansible/talos/configs/talosconfig}"
ENDPOINT="${TALOS_ENDPOINT:-10.140.0.40}"

RESOURCES=(
    # Kubernetes control plane (control-plane nodes only; empty on workers)
    apiserverconfigs admissioncontrolconfigs auditpolicyconfigs
    authenticationconfigs authorizationconfigs controllermanagerconfigs
    schedulerconfigs etcdencryptionconfigs staticpods
    bootstrapmanifestsconfigs extramanifestsconfigs manifests
    etcdconfigs etcdspecs certsans
    # Kubelet and node registration
    kubeletconfigs kubeletspecs kubeprismconfigs nodelabelspecs
    nodetaintspecs nodenames machinetypes
    # Host
    kernelmodulespecs kernelparamspecs timeserverspecs resolverspecs
    hostdnsconfigs registryconfigs discoveryconfigs volumeconfigs
    volumetrimschedules kubernetesaccessconfigs
)

mkdir -p "${OUT}"
chmod 700 "${OUT}"

for node in "${NODES[@]}"; do
    dir="${OUT}/${node}"
    mkdir -p "${dir}"
    for res in "${RESOURCES[@]}"; do
        # Volatile metadata changes on every reconcile and would drown the
        # real differences.
        talosctl get "${res}" --nodes "${node}" --endpoints "${ENDPOINT}" -o yaml 2>/dev/null |
            yq 'del(.node, .metadata.version, .metadata.created, .metadata.updated)' \
                >"${dir}/${res}.yaml" || true
        [[ -s "${dir}/${res}.yaml" ]] || rm -f "${dir}/${res}.yaml"
    done
    echo "${node}: $(find "${dir}" -name '*.yaml' | wc -l | tr -d ' ') resource files"
done
