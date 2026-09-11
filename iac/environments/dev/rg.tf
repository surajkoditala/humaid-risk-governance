module "rg" {
  source = "../../modules/terraform-azure-resourcegroup"

  tags        = var.tags
  enable_lock = false
}