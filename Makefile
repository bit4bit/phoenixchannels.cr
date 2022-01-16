.PHONY: lint fmt test

bin/ameba: bin/ameba.cr
	crystal build -o bin/ameba bin/ameba.cr

lint: bin/ameba
	bin/ameba

fmt:
	crystal tool format src
	crystal tool format spec

test:
	crystal spec
