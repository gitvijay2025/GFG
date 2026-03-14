# API Gateway

# Product API
resource "aws_api_gateway_rest_api" "product_api" {
  name        = "Product Service"
  description = "Product microservice REST API"
}

resource "aws_api_gateway_resource" "product_proxy" {
  rest_api_id = aws_api_gateway_rest_api.product_api.id
  parent_id   = aws_api_gateway_rest_api.product_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "product_proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.product_api.id
  resource_id   = aws_api_gateway_resource.product_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "product_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.product_api.id
  resource_id = aws_api_gateway_method.product_proxy_method.resource_id
  http_method = aws_api_gateway_method.product_proxy_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.product_lambda.invoke_arn
}

resource "aws_api_gateway_method" "product_root_method" {
  rest_api_id   = aws_api_gateway_rest_api.product_api.id
  resource_id   = aws_api_gateway_rest_api.product_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "product_root_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.product_api.id
  resource_id = aws_api_gateway_method.product_root_method.resource_id
  http_method = aws_api_gateway_method.product_root_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.product_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "product_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.product_lambda_integration,
    aws_api_gateway_integration.product_root_lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.product_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "product_api_gateway_permission" {
  statement_id  = "AllowAPIGatewayToInvokeProductLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.product_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.product_api.execution_arn}/*/*"
}


# Basket API
resource "aws_api_gateway_rest_api" "basket_api" {
  name = "Basket Service"
}

resource "aws_api_gateway_resource" "basket_proxy" {
  rest_api_id = aws_api_gateway_rest_api.basket_api.id
  parent_id   = aws_api_gateway_rest_api.basket_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "basket_proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.basket_api.id
  resource_id   = aws_api_gateway_resource.basket_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "basket_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.basket_api.id
  resource_id = aws_api_gateway_method.basket_proxy_method.resource_id
  http_method = aws_api_gateway_method.basket_proxy_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.basket_lambda.invoke_arn
}

resource "aws_api_gateway_method" "basket_root_method" {
  rest_api_id   = aws_api_gateway_rest_api.basket_api.id
  resource_id   = aws_api_gateway_rest_api.basket_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "basket_root_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.basket_api.id
  resource_id = aws_api_gateway_method.basket_root_method.resource_id
  http_method = aws_api_gateway_method.basket_root_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.basket_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "basket_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.basket_lambda_integration,
    aws_api_gateway_integration.basket_root_lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.basket_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "basket_api_gateway_permission" {
  statement_id  = "AllowAPIGatewayToInvokeBasketLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.basket_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.basket_api.execution_arn}/*/*"
}


# Order API
resource "aws_api_gateway_rest_api" "order_api" {
  name = "Order Service"
}

resource "aws_api_gateway_resource" "order_proxy" {
  rest_api_id = aws_api_gateway_rest_api.order_api.id
  parent_id   = aws_api_gateway_rest_api.order_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "order_proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  resource_id   = aws_api_gateway_resource.order_proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "order_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.order_api.id
  resource_id = aws_api_gateway_method.order_proxy_method.resource_id
  http_method = aws_api_gateway_method.order_proxy_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ordering_lambda.invoke_arn
}

resource "aws_api_gateway_method" "order_root_method" {
  rest_api_id   = aws_api_gateway_rest_api.order_api.id
  resource_id   = aws_api_gateway_rest_api.order_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "order_root_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.order_api.id
  resource_id = aws_api_gateway_method.order_root_method.resource_id
  http_method = aws_api_gateway_method.order_root_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ordering_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "order_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.order_lambda_integration,
    aws_api_gateway_integration.order_root_lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.order_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "order_api_gateway_permission" {
  statement_id  = "AllowAPIGatewayToInvokeOrderLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ordering_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.order_api.execution_arn}/*/*"
}
