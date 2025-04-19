terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

#------------------------------------------------------------
# 1) Static site bucket + public policy
#------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "website" {
  bucket = "spa-app-${random_string.suffix.result}"

  website {
    index_document = "index.html"
    error_document = "index.html"  # support client‑side routing
  }
}

# ------------------------------------------------------------
# 1.a) Allow public bucket policies on this bucket
# ------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true    # ACLs are already gone
  ignore_public_acls      = true
  block_public_policy     = false   # <-- allow your public policy
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "website_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.s3_policy.json
   depends_on = [
    aws_s3_bucket_public_access_block.website
  ]
}

#------------------------------------------------------------
# 2) Build & upload Go Lambda
#------------------------------------------------------------
# Trigger local build on changes to main.go
resource "null_resource" "build_lambda" {
  triggers = {
    src_hash = filesha256("lambda/main.go")
  }

  provisioner "local-exec" {
    command = <<EOT
      GOOS=linux GOARCH=amd64 go build -o main lambda/main.go
      zip lambda.zip main
    EOT
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "spa-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  function_name    = "api"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "bootstrap"
  runtime          = "provided.al2"

  # point at the ZIP you built in GitHub Actions
  filename         = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")
}


#------------------------------------------------------------
# 3) API Gateway to expose /hello
#------------------------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name        = "spa-api"
  description = "API Gateway for SPA"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_hello" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_proxy" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.get_hello.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deploy" {
  depends_on  = [aws_api_gateway_integration.lambda_proxy]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}
locals {
  rendered_index = templatefile(
    "${path.module}/index.html.tpl",
    {
      api_url = aws_api_gateway_deployment.deploy.invoke_url
    }
  )
}
#------------------------------------------------------------
# 4) Upload index.html with API URL interpolated
#------------------------------------------------------------
resource "aws_s3_bucket_object" "index" {
  bucket = aws_s3_bucket.website.id
  key    = "index.html"
  content      = local.rendered_index
  content_type = "text/html"
  acl          = "public-read"

}
