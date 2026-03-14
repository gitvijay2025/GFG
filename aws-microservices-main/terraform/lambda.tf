# Lambda Functions

# Product Lambda
data "archive_file" "product_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/product"
  output_path = "${path.root}/../product-lambda.zip"
}

resource "aws_lambda_function" "product_lambda" {
  function_name    = "productLambdaFunction"
  role             = aws_iam_role.product_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.product_lambda_zip.output_path
  source_code_hash = data.archive_file.product_lambda_zip.output_base64sha256

  environment {
    variables = {
      PRIMARY_KEY         = "id"
      DYNAMODB_TABLE_NAME = var.product_table_name
    }
  }
}

# Basket Lambda
data "archive_file" "basket_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/basket"
  output_path = "${path.root}/../basket-lambda.zip"
}

resource "aws_lambda_function" "basket_lambda" {
  function_name    = "basketLambdaFunction"
  role             = aws_iam_role.basket_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.basket_lambda_zip.output_path
  source_code_hash = data.archive_file.basket_lambda_zip.output_base64sha256

  environment {
    variables = {
      PRIMARY_KEY         = "userName"
      DYNAMODB_TABLE_NAME = var.basket_table_name
      EVENT_SOURCE        = "com.swn.basket.checkoutbasket"
      EVENT_DETAILTYPE    = "CheckoutBasket"
      EVENT_BUSNAME       = var.event_bus_name
    }
  }
}

# Ordering Lambda
data "archive_file" "ordering_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/ordering"
  output_path = "${path.root}/../ordering-lambda.zip"
}

resource "aws_lambda_function" "ordering_lambda" {
  function_name    = "orderingLambdaFunction"
  role             = aws_iam_role.ordering_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.ordering_lambda_zip.output_path
  source_code_hash = data.archive_file.ordering_lambda_zip.output_base64sha256

  environment {
    variables = {
      PRIMARY_KEY         = "userName"
      SORT_KEY            = "orderDate"
      DYNAMODB_TABLE_NAME = var.order_table_name
    }
  }
}

# SQS Event Source Mapping for Ordering Lambda
resource "aws_lambda_event_source_mapping" "ordering_lambda_sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.ordering_lambda.arn
  batch_size       = 1
}
