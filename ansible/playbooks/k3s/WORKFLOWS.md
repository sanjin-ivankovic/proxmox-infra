# K3s Operational Workflows

This document outlines standard operating procedures for managing the K3s cluster.

## 1. Routine Maintenance (Updates & Reboots)

**Objective:** Apply OS updates and reboot nodes without service interruption.

1.  **Pre-flight Check:**

    ```bash
    make health-check
    ```

    _Verify all checks pass (Nodes ready, no failed pods)._

2.  **OS Updates:**

    ```bash
    make system-update
    ```

3.  **Rolling Reboot:**

    ```bash
    make reboot
    ```

    _The playbook will automatically:_
    - Cordon node
    - Drain node (moving workloads to other available nodes)
    - Reboot
    - Wait for node to be Ready
    - Uncordon
    - Proceed to next node

4.  **Post-maintenance Verification:**
    ```bash
    make verify
    ```

## 2. Infrastructure Shutdown (UPS/Power Maintenance)

**Objective:** Gracefully shut down the entire cluster.

1.  **Preparation:**
    - Notify users of downtime.
    - Check for running critical jobs.
    - Run `make health-check`.

2.  **Shutdown:**

    ```bash
    make shutdown
    ```

    - Drains all worker nodes first.
    - Stops K3s services.
    - Shuts down VMs.

3.  **Recovery (Startup):**
    - Power on Proxmox hosts / VMs.
    - Wait for VMs to boot (ping check).
    - Run:
      ```bash
      make startup
      ```
    - This starts K3s services in correct order (Masters -> Workers) and uncordons nodes.

## 3. Emergency Node Drain

**Objective:** Rapidly remove workloads from a failing node.

1.  **Identify Node:** e.g., `k3s-worker-2`

2.  **Drain:**

    ```bash
    make drain-node HOST=k3s-worker-2
    ```

3.  **Investigate/Fix:** Perform hardware/software fix on the node.

4.  **Restore:**
    ```bash
    make maintenance-mode HOST=k3s-worker-2 STATE=disable
    ```

## 4. K3s Version Upgrade

1.  **Check Available Versions:**
    Check `defaults/main.yml` or K3s releases.

2.  **Run Upgrade:**
    ```bash
    make update
    ```

    - Prompts for version.
    - Performs rolling update (similar to reboot workflow).

## Troubleshooting

- **Pod stuck terminating:**
  Force delete (careful with stateful pods):

  ```bash
  kubectl delete pod <pod-name> --grace-period=0 --force
  ```

- **Node Not Ready:**
  Check K3s service status:

  ```bash
  systemctl status k3s        # On master
  systemctl status k3s-agent  # On worker
  ```

- **Diagnostics:**
  Generate a full report:
  ```bash
  make diagnostics
  ```
  Check `/tmp/k3s-diagnostics-*.txt`.
