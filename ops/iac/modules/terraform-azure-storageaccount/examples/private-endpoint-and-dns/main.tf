module "storage" {
  source = "../../" # In reality, this will be like "app.terraform.io/<tfc-org-name>/<registry-name>/azure"; version = "<version>"

  location            = "eastus2"
  resource_group_name = "rg-gh-dev-sandbox"
  tags = {
    "product"       = "gh"
    "environment"   = "dev"
    "customer"      = "myridius"
    "business_unit" = "banking"
    "owner"         = "devops"
    "region"        = "eastus2"
  }
  public_network_access_enabled = true #for staging and prod, this value will be false

  blob_properties = {
    cors_rule = [
      {
        allowed_headers    = ["*"]
        allowed_methods    = ["GET", "OPTIONS"]
        allowed_origins    = ["http://localhost:4200"]
        exposed_headers    = ["*"]
        max_age_in_seconds = 3600
      }
    ]
  }

  network_rules = {
    ip_rules = ["157.66.143.200", "210.14.21.200", "208.195.3.201"] #VPN IPs
    virtual_network_subnet_ids = [                                  #Subnets of the resources from which access is needed
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-cae-dev-sandbox-01",
      "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01"
    ]
  }

  # private end point creation
  private_endpoints = {
    st_pe_blob = {
      name                          = "pep-stblob-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]                       #Private DNS zone at subscription level
    }
    # Optional endpoints based on the requirement (like logic apps). Ideally only blob endpoint is enough for the storage accounts.
    st_pe_file = {
      name                          = "pep-stfile-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "file"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"] #Private DNS zone at subscription level
    }
    st_pe_queue = {
      name                          = "pep-stqueue-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "queue"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"] #Private DNS zone at subscription level
    }
    st_pe_table = {
      name                          = "pep-sttable-gh-dev-sandbox"
      subnet_resource_id            = "/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev-sandbox/providers/Microsoft.Network/virtualNetworks/vnet-gh-dev-sandbox/subnets/snet-pep-dev-sandbox-01" #PEP subnet ID
      subresource_name              = "table"
      private_dns_zone_resource_ids = ["/subscriptions/8ecc85fd-1e27-4f2e-8607-b77d8f3af452/resourceGroups/rg-gh-dev01/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"] #Private DNS zone at subscription level
    }
  }

}