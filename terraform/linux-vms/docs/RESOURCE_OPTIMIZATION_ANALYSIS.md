# K3s Cluster Resource Optimization Analysis

**Date:** 2026-01-21
**Cluster:** K3s Homelab (6 nodes: 3 masters + 3 workers)

## Executive Summary

The current K3s cluster is **significantly over-provisioned** across all
nodes. Based on actual usage patterns and the three-tier workload
architecture, we can safely reduce resource allocation by **~40% for
memory** and **~30% for CPU**, saving substantial Proxmox host resources
while maintaining adequate headroom.

---

## Current State vs. Actual Usage

### Master Nodes

<!-- markdownlint-disable MD013 -->
| Node | Config RAM | Actual RAM | Used RAM | Usage % | Config CPU | Actual CPU | Config Disk | Used Disk | Usage % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| master-1 | 6 GB* | 5.8 GB | 2.7 GB | **47%** | 3 cores | 3 cores | 100 GB | 27 GB | 29% |
| master-2 | 4 GB | 3.8 GB | 2.8 GB | **74%** | 3 cores | 3 cores | 100 GB | 23 GB | 24% |
| master-3 | 4 GB | 3.8 GB | 2.6 GB | **68%** | 3 cores | 3 cores | 100 GB | 30 GB | 31% |

**Note:** master-1 has been manually increased to 6GB (Terraform shows
4GB)

**Findings:**

- master-1 has extra 2GB manually allocated, but only using 2.7GB total
  (45% of 6GB)
- master-2 and master-3 are using 68-74% of their 4GB allocation
- Disk usage is very low (24-31%) - 100GB is excessive for control plane
  nodes
- CPU cores appear adequate (3 cores each)

### Worker Nodes

<!-- markdownlint-disable MD013 -->
| Node | Config RAM | Actual RAM | Used RAM | Usage % | Config CPU | Actual CPU | Config Disk | Used Disk | Usage % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| worker-1 | 8 GB* | 7.8 GB | 1.0 GB | **13%** | 4 cores | 4 cores | 500 GB | 65 GB | 14% |
| worker-2 | 6 GB | 7.8 GB* | 1.8 GB | **23%** | 4 cores | 4 cores | 500 GB | 65 GB | 14% |
| worker-3 | 6 GB | 7.8 GB* | 1.4 GB | **18%** | 4 cores | 4 cores | 500 GB | 62 GB | 13% |

**Note:** Workers show 7.8GB actual vs 6GB in Terraform - they've been
manually increased to 8GB

**Findings:**

- All workers manually increased from 6GB to 8GB, but usage is
  extremely low (13-23%)
- worker-1 (stateful tier) only using 1.0GB despite hosting
  PostgreSQL, Valkey, Prometheus, Grafana
- worker-2/3 (stateless tier) similarly underutilized
- 500GB disk allocation is reasonable for Longhorn distributed storage
- 4 CPU cores adequate for current workloads

### Cluster Totals

| Metric | Terraform Config | Actual Allocation | Actual Usage | Waste |
| --- | --- | --- | --- | --- |
| **Total RAM** | 30 GB | 37 GB | 13.2 GB | **64% unused** |
| **Total CPU** | 21 cores | 21 cores | Low utilization | Est. 50-60% idle |
| **Total Disk** | 1800 GB | 1800 GB | 332 GB | 18% used |

---

## Workload Distribution Analysis

### Infrastructure Tier (Control Plane = Masters 1-3)

**Running workloads:**

- K3s control plane components (3x replicas)
- ArgoCD (7 deployments + 1 StatefulSet)
- Traefik ingress (3 replicas)
- MetalLB controller (1 replica)
- Cert-manager + webhook
- Sealed Secrets controller
- Prometheus Operator + Kube State Metrics

**Resource characteristics:**

- Mostly lightweight controllers and operators
- ArgoCD is the heaviest (repo-server, application-controller)
- Traefik ingress handles all cluster traffic
- Low memory footprint (2-3GB per node reasonable)

### Stateful Tier (worker-1)

**Running workloads:**

- PostgreSQL (shared DB for affine, freshrss)
- Valkey (Redis-compatible cache)
- Prometheus (metrics storage - 50GB volume)
- Grafana (visualization - 10GB volume)
- Alertmanager (10GB volume)

**Resource characteristics:**

- Persistent storage workloads
- Prometheus is memory-intensive during scraping
- Current usage: 1.0GB despite heavy workloads
- Room for growth but 8GB is excessive

### Stateless Tier (workers 2-3)

**Running workloads:**

- FreshRSS RSS aggregator
- MetalLB speakers (DaemonSet on all nodes)
- Longhorn storage (DaemonSet on all nodes)
- Cloudflared tunnel
- Various other stateless apps

**Resource characteristics:**

- Lightweight web applications
- No persistent state (except Longhorn volumes)
- Even distribution across 2 nodes
- Very low current usage (1.4-1.8GB)

---

## Optimization Recommendations

### Option A: Conservative Reduction (Recommended)

Reduces over-allocation while maintaining comfortable headroom for
growth.

#### Option A: Master Nodes

<!-- markdownlint-disable MD013 -->
| Node | Current RAM | Recommended RAM | Savings | Current CPU | Recommended CPU | Savings |
| --- | --- | --- | --- | --- | --- | --- |
| master-1 | 6 GB | **4 GB** | -2 GB | 3 | **2** | -1 |
| master-2 | 4 GB | **4 GB** | 0 GB | 3 | **2** | -1 |
| master-3 | 4 GB | **4 GB** | 0 GB | 3 | **2** | -1 |

**Rationale:**

- master-2/3 already at 4GB and running fine (68-74% usage)
- master-1 reduced from 6GB to 4GB (currently only using 2.7GB)
- 2 CPU cores sufficient for K3s control plane + lightweight
  infrastructure
- Leaves ~25-30% headroom for spikes

#### Option A: Worker Nodes

<!-- markdownlint-disable MD013 -->
| Node | Current RAM | Recommended RAM | Savings | Current CPU | Recommended CPU | Savings | Disk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| worker-1 | 8 GB | **4 GB** | -4 GB | 4 | **3** | -1 | 500G ✓ |
| worker-2 | 8 GB | **4 GB** | -4 GB | 4 | **3** | -1 | 500G ✓ |
| worker-3 | 8 GB | **4 GB** | -4 GB | 4 | **3** | -1 | 500G ✓ |

**Rationale:**

- Current usage: 1.0-1.8GB (13-23% of 8GB)
- 4GB provides 2-2.8GB headroom (100-280% growth capacity)
- worker-1 hosts stateful workloads but still only using 1.0GB
- 3 CPU cores adequate for current + future workloads
- Keep 500GB disk for Longhorn distributed storage

#### Option A: Total Savings

- **RAM**: 37 GB → 24 GB (-13 GB = 35% reduction)
- **CPU**: 21 cores → 15 cores (-6 cores = 29% reduction)
- **Disk**: No change (usage justified for Longhorn)

---

### Option B: Aggressive Reduction (Maximum Efficiency)

Tighter resource allocation for maximum Proxmox host savings.

#### Option B: Master Nodes

<!-- markdownlint-disable MD013 -->
| Node | Current RAM | Recommended RAM | Savings | Current CPU | Recommended CPU | Savings |
| --- | --- | --- | --- | --- | --- | --- |
| master-1 | 6 GB | **3 GB** | -3 GB | 3 | **2** | -1 |
| master-2 | 4 GB | **3 GB** | -1 GB | 3 | **2** | -1 |
| master-3 | 4 GB | **3 GB** | -1 GB | 3 | **2** | -1 |

**Rationale:**

- Current peak usage: 2.8GB (master-2)
- 3GB provides minimal but adequate headroom
- Risk: Less room for control plane growth

#### Option B: Worker Nodes

<!-- markdownlint-disable MD013 -->
| Node | Current RAM | Recommended RAM | Savings | Current CPU | Recommended CPU | Savings | Disk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| worker-1 | 8 GB | **3 GB** | -5 GB | 4 | **2** | -2 | 500G ✓ |
| worker-2 | 8 GB | **3 GB** | -5 GB | 4 | **2** | -2 | 500G ✓ |
| worker-3 | 8 GB | **3 GB** | -5 GB | 4 | **2** | -2 | 500G ✓ |

**Rationale:**

- Current peak usage: 1.8GB (worker-2)
- 3GB provides 60-200% growth headroom
- Risk: May need adjustment if Prometheus data retention increases

#### Option B: Total Savings

- **RAM**: 37 GB → 18 GB (-19 GB = 51% reduction)
- **CPU**: 21 cores → 12 cores (-9 cores = 43% reduction)
- **Disk**: No change

---

## Implementation Plan

### Phase 1: Preparation

1. **Backup current state**

   ```bash
   # Snapshot all VMs in Proxmox before changes
   ```

2. **Monitor baseline metrics** (if monitoring enabled)

   ```bash
   # Capture 7-day peak usage from Prometheus/Grafana
   # Verify numbers align with current analysis
   ```

3. **Plan maintenance window**
   - Workers can be resized with rolling updates (one at a time)
   - Masters require brief control plane interruption
   - Total downtime: <15 minutes

### Phase 2: Update Terraform Configuration

**File:** `linux-vms.auto.tfvars` in
`terraform/linux-vms/instances/`

#### Option A (Conservative - Recommended)

```text
# Master nodes: 4GB RAM, 2 CPU cores
{
  hostname = "k3s-master-1"
  vmid = 440
  cores = 2              # Changed from 3
  memory = 4096          # Keep at 4GB (currently 6GB in Proxmox)
  disk_size = "100G"
  # ... rest unchanged
},
{
  hostname = "k3s-master-2"
  vmid = 441
  cores = 2              # Changed from 3
  memory = 4096          # Keep at 4GB
  # ... rest unchanged
},
{
  hostname = "k3s-master-3"
  vmid = 442
  cores = 2              # Changed from 3
  memory = 4096          # Keep at 4GB
  # ... rest unchanged
},

# Worker nodes: 4GB RAM, 3 CPU cores
{
  hostname = "k3s-worker-1"
  vmid = 450
  cores = 3              # Changed from 4
  memory = 4096          # Changed from 6144 (currently 8GB in Proxmox)
  disk_size = "500G"
  # ... rest unchanged
},
{
  hostname = "k3s-worker-2"
  vmid = 451
  cores = 3              # Changed from 4
  memory = 4096          # Changed from 6144
  # ... rest unchanged
},
{
  hostname = "k3s-worker-3"
  vmid = 452
  cores = 3              # Changed from 4
  memory = 4096          # Changed from 6144
  # ... rest unchanged
},
```

#### Option B (Aggressive)

```text
# Master nodes: 3GB RAM, 2 CPU cores
memory = 3072  # Changed from 4096
cores = 2      # Changed from 3

# Worker nodes: 3GB RAM, 2 CPU cores
memory = 3072  # Changed from 6144
cores = 2      # Changed from 4
```

### Phase 3: Apply Changes

```bash
cd /home/user/projects/proxmox-infra/terraform/linux-vms

# Review planned changes
make plan

# Expected output:
#   ~ k3s-master-1: cores 3→2, memory 6144→4096
#   ~ k3s-master-2: cores 3→2
#   ~ k3s-master-3: cores 3→2
#   ~ k3s-worker-1: cores 4→3, memory 8192→4096
#   ~ k3s-worker-2: cores 4→3, memory 8192→4096
#   ~ k3s-worker-3: cores 4→3, memory 8192→4096

# Apply changes (requires VM shutdown/restart)
make apply

# VMs will restart with new resource allocation
```

### Phase 4: Validation

1. **Verify cluster health**

   ```bash
   kubectl get nodes
   kubectl get pods -A | grep -v Running
   ```

2. **Monitor resource usage post-change**

   ```bash
   # Check each node
   for i in {1..3}; do
     ssh maintainer@10.40.0.4$i "free -h"
     ssh maintainer@10.40.0.5$((i-1)) "free -h"
   done
   ```

3. **Watch for OOM or CPU throttling** (1-2 weeks)

   - If master nodes exceed 80% memory: increase to 5GB
   - If worker-1 exceeds 80%: increase to 5GB (stateful workloads)
   - If CPU wait times increase: restore original core counts

### Phase 5: Sync ArgoCD

After Terraform apply completes:

1. Navigate to ArgoCD UI: <https://argo.example.com>
2. Manually sync all applications (auto-sync disabled)
3. Verify all pods reschedule successfully on resized nodes

---

## Risk Assessment

### Low Risk

- **Disk**: No changes proposed (already efficiently utilized)
- **Worker-2/3**: Extremely low utilization (18-23%), safe to reduce
- **CPU reduction**: K3s is not CPU-intensive for current workload

### Medium Risk

- **Master nodes**: Reducing from 4GB to 3GB (Option B) leaves little headroom
- **worker-1**: Stateful workloads may grow with Prometheus retention

### Mitigation Strategies

1. **Gradual rollout**: Apply to one worker first, monitor for 48h
2. **Monitoring alerts**: Set up alerts for >80% memory usage
3. **Quick rollback**: Terraform makes it easy to increase resources if
   needed
4. **Kubernetes limits**: Set memory requests/limits on heavy pods
   (Prometheus, PostgreSQL)

---

## Alternative: Resource Requests/Limits

Instead of (or in addition to) reducing VM resources, configure
Kubernetes resource management:

### Example for Prometheus (currently no limits)

```text
# infrastructure/monitoring/values.yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 2Gi
```

This would:

- Guarantee 1GB for Prometheus
- Prevent it from using >2GB
- Allow Kubernetes to better pack pods

**Recommendation:** Implement Option A + add resource limits to top
consumers (Prometheus, PostgreSQL, Grafana).

---

## Long-term Optimization

### Kubernetes Resource Management

After implementing VM resizing, add resource requests/limits to prevent
over-allocation:

1. **Prometheus**: 1-2GB limit (currently unbounded)
2. **PostgreSQL**: 512MB-1GB limit
3. **Valkey**: 256MB-512MB limit
4. **Grafana**: 256MB-512MB limit

### Monitoring Setup

If not already enabled, deploy the monitoring stack to track:

- Node memory/CPU usage trends
- Pod memory/CPU usage
- OOM kills
- CPU throttling events

This data will validate the optimization and catch issues early.

---

## Conclusion

**Recommended Action**: **Option A (Conservative Reduction)**

- Reduces cluster RAM from 37GB to 24GB (35% savings)
- Reduces cluster CPU from 21 to 15 cores (29% savings)
- Maintains comfortable 25-30% headroom for growth
- Low risk of performance issues
- Easy to increase if needed

**Expected Benefits:**

- Free up 13GB RAM on Proxmox host
- Free up 6 CPU cores for other VMs
- Improved resource density
- More accurate resource tracking via Terraform

**Next Steps:**

1. Review this analysis and choose Option A or B
2. Schedule maintenance window
3. Update Terraform configuration
4. Test `make plan` to verify changes
5. Apply with `make apply`
6. Monitor for 1-2 weeks and adjust if needed
