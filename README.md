# reqsai-infra

Infraestructura como código de ReqsAI.

| Directorio | Contenido |
| --- | --- |
| `bootstrap/` | Bucket S3 de estado de Terraform (se aplica una sola vez por cuenta). |
| `envs/production/` | Stack completo: VPC, ECS Fargate, ALB, RDS, CloudFront + S3, ACM, Route53, Secrets Manager, OIDC de GitHub. |
| `envs/ec2-compose/` | Entorno económico: una sola EC2 con Docker Compose (Postgres + pgvector, API, web y Caddy con HTTPS). |
| `compose/`, `ansible/`, `scripts/` | Stack de Compose, configuración del host con Ansible y build/push de imágenes para `envs/ec2-compose`. |
| `.github/workflows/deploy-mvp.yml` | Único despliegue de `envs/ec2-compose`: la imagen de una release por digest desde GHCR (o un build arm64 manual), respaldo de la base y Ansible sobre SSM, con aprobación en `produccion` e interruptor `ENABLE_REQSAI_INFRA_DEPLOY`. |
| `.github/workflows/release.yml` | En `release/x.y.z` y `hotfix/x.y.z`: CI → candidata `vx.y.z-rc.N` (pre-release con `ansible/` + `compose/`, SHA-256 y hash del árbol) → verificación del stack Compose (`scripts/verify-stack.sh`) → PR a `main`. |
| `.github/workflows/produccion.yml` | En `main`: la candidata con el mismo árbol → `deploy-mvp.yml` (aprobación) → tag `vx.y.z` + release → PR de vuelta a `develop`. |
| `.github/workflows/rollback.yml` | Vuelve a aplicar `ansible/` y `compose/` de un release anterior. |
| `.github/workflows/ci.yml` | En cada PR y push a `main`, `develop`, `release/**`, `hotfix/**`: actionlint + shellcheck, shellcheck de `scripts/` y `.github/scripts/`, `terraform fmt -check` y sintaxis de Ansible. |

La versión del repo está en `VERSION`; el flujo de releases (modelo C + tag al final) está en la
[sección 14 de la guía](docs/deploy-ec2-docker-compose.md#14-despliegue-continuo-con-github-actions).

Guías:

- [Despliegue económico en una sola EC2 con Docker Compose](docs/deploy-ec2-docker-compose.md)
