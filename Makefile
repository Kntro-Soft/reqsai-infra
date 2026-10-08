TF_DIR := envs/ec2-compose
TF_OCI_DIR := envs/oci
ANSIBLE_DIR := ansible
VAULT_ARGS ?= --ask-vault-pass
INVENTORY ?= inventory/hosts.yml

.PHONY: images images-archive inventory inventory-oci galaxy deploy redeploy backup-now

images:
	scripts/build-and-push-images.sh

images-archive:
	scripts/save-images.sh

inventory:
	terraform -chdir=$(TF_DIR) output -raw ansible_inventory > $(ANSIBLE_DIR)/inventory/hosts.yml

inventory-oci:
	terraform -chdir=$(TF_OCI_DIR) output -raw ansible_inventory > $(ANSIBLE_DIR)/inventory/oci.yml

galaxy:
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

deploy:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --inventory $(INVENTORY) $(VAULT_ARGS)

redeploy:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --inventory $(INVENTORY) --tags app $(VAULT_ARGS)

backup-now:
	cd $(ANSIBLE_DIR) && ansible reqsai --inventory $(INVENTORY) --become -m ansible.builtin.command -a /usr/local/sbin/reqsai-backup $(VAULT_ARGS)
