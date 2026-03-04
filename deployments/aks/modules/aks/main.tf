resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.name_prefix}-aks-${var.suffix_hex}"
  location            = var.location
  resource_group_name  = var.resource_group_name
  dns_prefix          = "${var.name_prefix}-${var.suffix_hex}"

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.vm_size
    temporary_name_for_rotation = "systemtemp"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count                 = var.enable_spot_node_pool ? 1 : 0
  name                  = var.spot_node_pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.spot_vm_size
  node_count            = var.spot_node_count

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = var.spot_max_price

  orchestrator_version          = null
  temporary_name_for_rotation   = "spottemp"

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = merge(var.tags, { "pool" = var.spot_node_pool_name })
}

resource "null_resource" "aks_dns_ready" {
  provisioner "local-exec" {
    command = "bash -c 'API_FQDN=\"${azurerm_kubernetes_cluster.aks.fqdn}\"; echo \"Waiting for AKS API server DNS: $API_FQDN\"; for i in {1..60}; do echo \"Attempt $i/60: Checking DNS...\"; if getent hosts \"$API_FQDN\" > /dev/null 2>&1 || nslookup \"$API_FQDN\" > /dev/null 2>&1 || host \"$API_FQDN\" > /dev/null 2>&1; then echo \"✓ DNS resolved: $(getent hosts \"$API_FQDN\" 2>/dev/null || echo OK)\"; exit 0; fi; sleep 10; done; echo \"WARNING: DNS timeout after 600s. Continuing anyway...\"; exit 0'"
  }

  triggers = {
    aks_id    = azurerm_kubernetes_cluster.aks.id
    aks_fqdn  = azurerm_kubernetes_cluster.aks.fqdn
    node_pool = try(azurerm_kubernetes_cluster_node_pool.spot[0].id, "none")
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_kubernetes_cluster_node_pool.spot
  ]
}

resource "time_sleep" "aks_control_plane_ready" {
  depends_on      = [null_resource.aks_dns_ready]
  create_duration = "30s"
}
