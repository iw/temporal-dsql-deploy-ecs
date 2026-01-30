# Alloy Sidecar Module

## Purpose

Generates Grafana Alloy sidecar container definitions for metrics and log collection. This module creates SSM parameters for Alloy configuration and outputs container definitions that can be included in any ECS task definition to enable consistent observability across all services.

Alloy replaces ADOT sidecars with a unified collector that:
- Collects logs via Docker socket and sends to Loki
- Scrapes Prometheus metrics and sends to Amazon Managed Prometheus
- Provides a single sidecar for both logs and metrics

## Inputs

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| project_name | string | Project name for resource naming | required |
| service_name | string | Service name for labeling (e.g., history, matching) | required |
| prometheus_remote_write_endpoint | string | AMP remote write endpoint URL | required |
| loki_endpoint | string | Loki push endpoint URL | required |
| region | string | AWS region | required |
| alloy_image | string | Alloy container image | "grafana/alloy:v1.12.2" |

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| init_container_definition | object | Init container JSON for fetching config from SSM |
| sidecar_container_definition | object | Alloy sidecar container JSON |
| ssm_parameter_arn | string | ARN of the SSM parameter with Alloy config |
| docker_socket_volume | object | Docker socket volume definition |
| alloy_config_volume | object | Alloy config volume definition |

## Usage Example

```hcl
module "alloy_history" {
  source = "../../modules/alloy-sidecar"

  project_name                     = "temporal-dev"
  service_name                     = "history"
  prometheus_remote_write_endpoint = module.observability.prometheus_remote_write_endpoint
  loki_endpoint                    = "${module.observability.loki_endpoint}/loki/api/v1/push"
  region                           = "eu-west-1"
  alloy_image                      = "grafana/alloy:v1.12.2"
}

# Then use in temporal-service module:
module "temporal_history" {
  source = "../../modules/temporal-service"
  # ... other variables ...
  alloy_init_container    = module.alloy_history.init_container_definition
  alloy_sidecar_container = module.alloy_history.sidecar_container_definition
}
```

## Architecture

The module creates:

1. **SSM Parameter**: Stores the Alloy configuration with service-specific labels
2. **Init Container**: Fetches the config from SSM at task startup
3. **Sidecar Container**: Runs Alloy to collect logs and metrics

```
┌─────────────────────────────────────────────────────────────────┐
│                    ECS Task Definition                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  Init Container │───▶│  SSM Parameter  │                    │
│  │  (aws-cli)      │    │  (Alloy config) │                    │
│  └────────┬────────┘    └─────────────────┘                    │
│           │                                                     │
│           │ writes config to /etc/alloy/                        │
│           ▼                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  Alloy Sidecar  │───▶│  Main Container │                    │
│  │  (collector)    │    │  (Temporal svc) │                    │
│  └────────┬────────┘    └─────────────────┘                    │
│           │                                                     │
│           │ scrapes metrics (localhost:9090)                    │
│           │ collects logs (Docker socket)                       │
│           ▼                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  Loki           │    │  AMP            │                    │
│  │  (logs)         │    │  (metrics)      │                    │
│  └─────────────────┘    └─────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Volume Requirements

Task definitions using this module must include these volumes:

```hcl
volume {
  name = "docker-socket"
  host_path = "/var/run/docker.sock"
}

volume {
  name = "alloy-config"
}
```

Or use the module outputs:
- `docker_socket_volume` - Docker socket volume definition
- `alloy_config_volume` - Alloy config volume definition
