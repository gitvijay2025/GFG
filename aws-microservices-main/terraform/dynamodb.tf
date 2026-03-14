# DynamoDB Tables

resource "aws_dynamodb_table" "product_table" {
  name           = var.product_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "basket_table" {
  name           = var.basket_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userName"

  attribute {
    name = "userName"
    type = "S"
  }
}

resource "aws_dynamodb_table" "order_table" {
  name           = var.order_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userName"
  range_key      = "orderDate"

  attribute {
    name = "userName"
    type = "S"
  }

  attribute {
    name = "orderDate"
    type = "S"
  }
}
