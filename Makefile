NS ?= kaspergrubbe
IMAGE_NAME ?= infping-rb
VERSION ?= latest

compose-rebuild:
	docker-compose build --force-rm --no-cache

compose-clean:
	docker-compose down --remove-orphans

run:
	docker-compose up

build:
	docker build --compress --no-cache --file Dockerfile --tag $(NS)/$(IMAGE_NAME):$(VERSION) .

push:
	docker push $(NS)/$(IMAGE_NAME):$(VERSION)

release:
	make build
	make push
	git tag -a v$(VERSION) -m 'Tagging for release: $(VERSION)'
	git push origin v$(VERSION)

default: build
