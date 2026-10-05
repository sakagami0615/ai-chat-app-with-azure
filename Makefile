.PHONY: up deploy down

up:
	bash infra/sandbox/hello-world/manage.sh up

deploy:
	bash infra/sandbox/hello-world/manage.sh deploy

down:
	bash infra/sandbox/hello-world/manage.sh down
