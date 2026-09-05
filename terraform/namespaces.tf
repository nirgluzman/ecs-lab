# Cloud Map namespaces for Service Connect.
#
# A namespace is a discovery boundary, not a placement boundary: all four
# services run in the one cluster, but a client can only resolve aliases inside
# its own namespace. That is what keeps the nginx experiment and the
# application stack from seeing each other while sharing the same
# infrastructure.
#
# HTTP namespaces, not private DNS: Service Connect resolves names through the
# sidecar it injects, so there is no Route 53 hosted zone to pay for or clean
# up, and the names exist only inside the mesh.
#
# A namespace is the only Cloud Map resource declared here, because Cloud Map is
# the registry discovery actually reads and ECS fills it in on its own. For each
# service with discoverable = true, ECS creates a Cloud Map service named after
# its discovery_name, then registers and deregisters an instance per task as
# tasks start and stop. The sidecar resolves an alias by reading that registry,
# which is why "backend:8000" keeps working across a deployment that replaces
# every task behind it.
#
# So none of it appears in this configuration: no aws_service_discovery_service,
# no instances. Two consequences worth knowing - Terraform cannot show you what
# is registered (use `aws servicediscovery list-services`), and a destroy can
# race, failing to delete a namespace while ECS is still removing its services.
# Re-running destroy clears it.
#
# The alternative, ECS Service Discovery, is where you would declare those
# services by hand and wire them in through service_registries instead. It hands
# clients task IPs over real DNS, so a client that cached a record keeps dialling
# a task that no longer exists.

# frontend -> backend -> mongodb
resource "aws_service_discovery_http_namespace" "app" {
  name        = "${var.name_prefix}-app"
  description = "application stack: frontend, backend, mongodb"
}

# nginx - standalone experiment, isolated from the application stack
resource "aws_service_discovery_http_namespace" "nginx" {
  name        = "${var.name_prefix}-nginx"
  description = "nginx stack"
}
