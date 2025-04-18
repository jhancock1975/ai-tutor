output "website_url" {
  description = "Static site endpoint"
  value       = aws_s3_bucket.website.website_endpoint
}

output "api_url" {
  description = "GET /hello endpoint"
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.deploy.stage_name}/hello"
}
