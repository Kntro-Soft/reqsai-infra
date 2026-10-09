# reqsai-infra

Infraestructura como código de ReqsAI.

| Directorio | Contenido |
| --- | --- |
| `bootstrap/` | Bucket S3 de estado de Terraform (se aplica una sola vez por cuenta). |
| `envs/production/` | Stack completo: VPC, ECS Fargate, ALB, RDS, CloudFront + S3, ACM, Route53, Secrets Manager, OIDC de GitHub. |
| `envs/ec2-compose/` | Entorno económico: una sola EC2 con Docker Compose (Postgres + pgvector, API, web y Caddy con HTTPS). |
| `compose/`, `ansible/`, `scripts/` | Stack de Compose, configuración del host con Ansible y build/push de imágenes para `envs/ec2-compose`. |
| `.github/workflows/deploy-mvp.yml` | Despliegue de `envs/ec2-compose`: build arm64 (o la imagen de una release en GHCR) y Ansible sobre SSM, con aprobación en `produccion` e interruptor `ENABLE_REQSAI_INFRA_DEPLOY`. |
| `.github/workflows/ci.yml` | En cada PR: actionlint + shellcheck de los workflows, shellcheck de `scripts/` y `terraform fmt -check`. |

Guías:

- [Despliegue económico en una sola EC2 con Docker Compose](docs/deploy-ec2-docker-compose.md)
