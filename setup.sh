#!/usr/bin/env bash
set -e

echo "→ Initializing Go module and adding aws-lambda-go..."
cd lambda

# Initialize module if needed (you can adjust the module path as desired)
if [ ! -f go.mod ]; then
  go mod init spa-lambda
fi

# Fetch the Lambda helper package
go get github.com/aws/aws-lambda-go/lambda@latest

# Clean up go.mod & go.sum
go mod tidy

echo "✓ Go module ready: $(pwd)/go.mod"
