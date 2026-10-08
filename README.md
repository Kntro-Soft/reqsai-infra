# reqsai-infra

Infraestructura como código de ReqsAI.

| Directorio | Contenido |
| --- | --- |
| `bootstrap/` | Bucket S3 de estado de Terraform (se aplica una sola vez por cuenta). |
| `envs/production/` | Stack completo: VPC, ECS Fargate, ALB, RDS, CloudFront + S3, ACM, Route53, Secrets Manager, OIDC de GitHub. |
| `envs/ec2-compose/` | Entorno económico: una sola EC2 con Docker Compose (Postgres + pgvector, API, web y Caddy con HTTPS). |
| `compose/`, `ansible/`, `scripts/` | Stack de Compose, configuración del host con Ansible y build/push de imágenes para `envs/ec2-compose`. |
| `envs/oci/`, `modules/oci-compose-host/` | Mismo stack de Compose en una VM Ampere A1 de OCI Always Free (destino de la migración desde `envs/ec2-compose`). |
| `.github/workflows/deploy-mvp.yml` | Despliegue continuo: build arm64 en GitHub Actions y Ansible sobre SSM (AWS) o SSH (OCI, `target=oci`). |
| `scripts/oci-migration/` | Migración de datos y configuración de AWS a OCI, y su ensayo local. |

Guías:

- [Despliegue económico en una sola EC2 con Docker Compose](docs/deploy-ec2-docker-compose.md)
- [Migración de producción de AWS a OCI Always Free](docs/oci-migration.md)
