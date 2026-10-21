# GitHub Actions reaches Azure with OIDC: a user-assigned managed identity trusts the tokens GitHub issues to
# deploy jobs of the environment mvp of reqsai-infra, so no Azure secret lives in GitHub. The identity can only
# change this NSG: the deploy opens SSH (22) to the runner's address for the run and closes it afterwards.

resource "azurerm_user_assigned_identity" "github_deploy" {
  name                = "${local.name}-github-deploy"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_deploy" {
  name                      = "github-${var.github_repository_name}-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_owner}/${var.github_repository_name}:environment:${var.github_environment}"
}

resource "azurerm_role_assignment" "github_deploy_nsg" {
  scope                = azurerm_network_security_group.app.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.github_deploy.principal_id
}
