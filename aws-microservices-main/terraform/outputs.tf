output "product_api_endpoint" {
  description = "The invoke URL for the Product API"
  value       = aws_api_gateway_deployment.product_api_deployment.invoke_url
}

output "basket_api_endpoint" {
  description = "The invoke URL for the Basket API"
  value       = aws_api_gateway_deployment.basket_api_deployment.invoke_url
}

output "order_api_endpoint" {
  description = "The invoke URL for the Order API"
  value       = aws_api_gateway_deployment.order_api_deployment.invoke_url
}
