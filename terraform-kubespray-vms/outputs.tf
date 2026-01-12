output "k8s_vip" {
  value = var.k8s_vip
}

output "nodes" {
  value = {
    for name, cfg in local.nodes : name => cfg.ip
  }
}

