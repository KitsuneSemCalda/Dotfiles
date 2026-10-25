.PHONY: build test check homologate
build:
	go build -trimpath -o bin/inferctl ./cmd/inferctl
test:
	go test -race ./...
	python3 -m unittest discover -s tools -p 'test_*.py'
check: test
	go vet ./...

homologate:
	python3 tools/homologate.py $(ARGS)
