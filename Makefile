NS ?= kaspergrubbe
IMAGE_NAME ?= infping-rb
VERSION ?= latest

build:
	docker-compose build --force-rm --no-cache

clean:
	docker-compose down --remove-orphans

run:
	docker-compose up

push:
	docker push $(NS)/$(IMAGE_NAME):$(VERSION)

release: build
	make push -e VERSION=$(VERSION)

default: build
