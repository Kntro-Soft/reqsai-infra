# Producción en Azure (envs/azure-vm)

Desde el 2026-10-21 la producción de ReqsAI (`reqsai.tech`) corre en una VM de Azure, con la misma forma que tenía en
AWS: Docker Compose con la API, la web, Caddy y Postgres con pgvector en un solo host, provisionado por `ansible/site.yml`.

| Pieza | Valor |
| --- | --- |
| Suscripción | Azure for Students (regiones permitidas: canadacentral, chilecentral, northcentralus, westus, mexicocentral) |
| Región | `northcentralus`: de las permitidas, una de las dos que ofrecen tamaños Arm64 B v2 |
| Tamaño | `Standard_B2pls_v2` (2 vCPU Arm64, 4 GiB): las imágenes de la API y la web son linux/arm64 |
| Disco | 32 GiB StandardSSD_LRS (sistema, imágenes, volumen de Postgres y backups locales) |
| Red | VNet propia, NSG con 80/TCP, 443/TCP, 443/UDP y 8080/TCP solo desde `admin_cidrs`; el 22 lo abre cada deploy solo para su runner |
| IP | IPv4 estática Standard, destino del registro A de `reqsai.tech` |

## Acceso del operador

La red del operador solo deja salir 80, 443, 8080 y 993, por eso `sshd` también escucha en el 8080, abierto solo a
`admin_cidrs`: `terraform -chdir=envs/azure-vm output -raw ssh_command`.

## Terraform

El estado es local (`envs/azure-vm/terraform.tfstate`, ignorado por Git) como en `envs/ec2-compose`. Las variables van en
`terraform.tfvars` (ignorado); ver `terraform.tfvars.example`. `deploy_ssh_public_key` es la mitad pública del secreto
`DEPLOY_SSH_PRIVATE_KEY` del entorno `mvp`.

## Deploy desde GitHub (OIDC)

`deploy-mvp.yml` entra a Azure con OIDC: la identidad administrada `reqsai-mvp-github-deploy`
(`envs/azure-vm/github-deploy.tf`) confía en los tokens que GitHub emite a los jobs del entorno `mvp` de
`Kntro-Soft/reqsai-infra` (sujeto `repo:Kntro-Soft/reqsai-infra:environment:mvp`) y solo tiene `Network Contributor`
sobre el NSG. En GitHub no hay ningún secreto de Azure: las variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` y `AZURE_NSG_NAME` del entorno `mvp` salen de
`terraform output github_deploy`.

Cada deploy abre el 22 solo para la IP de su runner (regla `deploy-<run>-<intento>`, prioridad 300), entra por SSH a
`DEPLOY_HOST` con el secreto `DEPLOY_SSH_PRIVATE_KEY` y cierra la regla al terminar, aunque falle. Las extra-vars (`ANSIBLE_EXTRA_VARS_B64`) llevan la llave
de deploy sin la restricción `from="127.0.0.1"` que tenía el túnel de SSM.

## Migración desde AWS

1. `terraform apply` en `envs/azure-vm`; roles `base`, `docker`, `app` y `backup` con las mismas imágenes que corrían en AWS.
2. API y web de AWS detenidas, `pg_dump -Fc`, copia a Azure, `pg_restore` en una base vacía (checksum y conteos comprobados).
3. El Caddy de AWS quedó como proxy hacia Azure mientras el DNS (TTL 7200 s) dejaba de apuntar a AWS.
4. Registro A de `reqsai.tech` → IP de Azure; después, baja de todos los recursos de AWS.
