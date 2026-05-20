# cluster-tags.auto.tfvars — Define developer access per cluster
#
# Add clusters here to grant developer access. The main.tf dynamic lookup
# will automatically create access entries and policy associations.
#
# Access levels:
#   view  → AmazonEKSViewPolicy (read-only, safe for all engineers)
#   edit  → AmazonEKSEditPolicy (deploy workloads, manage configmaps/secrets)
#   admin → AmazonEKSClusterAdminPolicy (full cluster admin — use sparingly)

cluster_access_config = {
  # Example: uncomment and adjust to your clusters
  #
  # "my-app-prod" = {
  #   access_level = "view"
  # }
  #
  # "my-app-staging" = {
  #   access_level = "edit"
  # }
  #
  # "my-app-dev" = {
  #   access_level = "edit"
  # }
}
