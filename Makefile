.PHONY: setup build package clean

# 1) Ensure go.mod & deps
setup:
	@./setup.sh

# 2) Build _inside_ lambda/ so that go.mod is picked up
build:
	cd lambda && \
	GOOS=linux GOARCH=amd64 go build -o bootstrap main.go && \
	mv bootstrap ..

# 3) Full package: setup → build → zip
package: setup build
	zip -j lambda.zip bootstrap

# 4) Cleanup all artifacts
clean:
	rm -f lambda.zip bootstrap
	rm -f lambda/go.mod lambda/go.sum
