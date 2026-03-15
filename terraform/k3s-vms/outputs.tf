# ============================================================================
# K3s VMs - Outputs
# ============================================================================

# TODO: Uncomment when activating this project

# output "vm_details" {
#   description = "Details of all K3s VMs"
#   value       = length(var.k3s_vm_instances) > 0 ? module.k3s_vms[0].vm_details : {}
# }

# output "vm_ips" {
#   description = "Map of hostnames to IP addresses for K3s VMs"
#   value       = length(var.k3s_vm_instances) > 0 ? module.k3s_vms[0].vm_ips : {}
# }

# output "ansible_info" {
#   description = "Inventory data for Ansible consumption"
#   value = length(var.k3s_vm_instances) > 0 ? {
#     for hostname, instance in module.k3s_vms[0].vms :
#     hostname => {
#       ansible_host                 = split("/", local.instances_map[hostname].ip)[0]
#       ansible_user                 = "root"
#       ansible_ssh_private_key_file = module.ssh_keys.ssh_key_paths[hostname].private
#       k3s_role                     = local.instances_map[hostname].k3s_role
#       groups                       = try(local.instances_map[hostname].tags, [])
#     }
#   } : {}
# }
