TF_DIR := envs/ec2-compose
ANSIBLE_DIR := ansible
VAULT_ARGS ?= --ask-vault-pass

.PHONY: images images-archive inventory galaxy deploy redeploy backup-now

images:
	scripts/build-and-push-images.sh

images-archive:
	scripts/save-images.sh

inventory:
	terraform -chdir=$(TF_DIR) output -raw ansible_inventory > $(ANSIBLE_DIR)/inventory/hosts.yml

galaxy:
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

deploy:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml $(VAULT_ARGS)

redeploy:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags app $(VAULT_ARGS)

backup-now:
	cd $(ANSIBLE_DIR) && ansible reqsai --become -m ansible.builtin.command -a /usr/local/sbin/reqsai-backup $(VAULT_ARGS)
