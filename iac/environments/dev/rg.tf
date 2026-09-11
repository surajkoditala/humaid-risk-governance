# This is the main.tf file for the test environment
# dummy change to validate dev-pr-review.yml + dev-tf-deploy.yml end to end
module "rg" {
  source = "../../modules/terraform-azure-resourcegroup"


  tags        = var.tags
  enable_lock = false
}