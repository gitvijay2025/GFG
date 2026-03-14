# IAM Roles and Policies for Lambda Functions

# Product Lambda
resource "aws_iam_role" "product_lambda_role" {
  name = "ProductLambdaRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "product_dynamodb_access" {
  name = "ProductDynamoDBAccess"
  role = aws_iam_role.product_lambda_role.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.product_table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "product_lambda_basic_execution" {
  role       = aws_iam_role.product_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Basket Lambda
resource "aws_iam_role" "basket_lambda_role" {
  name = "BasketLambdaRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "basket_dynamodb_and_eventbridge_access" {
  name = "BasketDynamoDBAndEventBridgeAccess"
  role = aws_iam_role.basket_lambda_role.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBAccess"
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.basket_table.arn
      },
      {
        Sid      = "EventBridgeAccess"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.swn_event_bus.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basket_lambda_basic_execution" {
  role       = aws_iam_role.basket_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Ordering Lambda
resource "aws_iam_role" "ordering_lambda_role" {
  name = "OrderingLambdaRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "order_dynamodb_access" {
  name = "OrderDynamoDBAccess"
  role = aws_iam_role.ordering_lambda_role.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.order_table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ordering_lambda_basic_execution" {
  role       = aws_iam_role.ordering_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ordering_lambda_sqs_execution" {
  role       = aws_iam_role.ordering_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}
