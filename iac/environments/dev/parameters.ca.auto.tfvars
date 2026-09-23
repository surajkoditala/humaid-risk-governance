ASPNETCORE_ENVIRONMENT = "Development"
min_replicas           = 1
max_replicas           = 1

ingress = {
  allow_insecure_connections = false
  external_enabled           = true
  target_port                = 8080
  cors = {
    allowed_origins = ["*"]
    allowed_methods = ["*"]
    allowed_headers = ["*"]
    exposed_headers = ["*"]
  }
  traffic_weight = [
    {
      latest_revision = true
      percentage      = 100
    }
  ]
}

backend_app_min_replicas = 1
backend_app_max_replicas = 1

backend_app_ingress = {
  allow_insecure_connections = false
  external_enabled           = false
  target_port                = 8080

  traffic_weight = [
    {
      latest_revision = true
      percentage      = 100
    }
  ]
}