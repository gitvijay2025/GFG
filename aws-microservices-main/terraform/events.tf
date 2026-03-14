# SQS Queue
resource "aws_sqs_queue" "order_queue" {
  name = var.order_queue_name
}

# EventBridge Event Bus
resource "aws_cloudwatch_event_bus" "swn_event_bus" {
  name = var.event_bus_name
}

resource "aws_cloudwatch_event_rule" "checkout_basket_rule" {
  name          = "CheckoutBasketRule"
  description   = "When Basket microservice checkout the basket"
  event_bus_name = aws_cloudwatch_event_bus.swn_event_bus.name

  event_pattern = jsonencode({
    "source"      = ["com.swn.basket.checkoutbasket"],
    "detail-type" = ["CheckoutBasket"]
  })
}

resource "aws_cloudwatch_event_target" "sqs_target" {
  rule      = aws_cloudwatch_event_rule.checkout_basket_rule.name
  target_id = "SQS"
  arn       = aws_sqs_queue.order_queue.arn
  event_bus_name = aws_cloudwatch_event_bus.swn_event_bus.name
}

resource "aws_sqs_queue_policy" "order_queue_policy" {
  queue_url = aws_sqs_queue.order_queue.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action = "sqs:SendMessage",
        Resource = aws_sqs_queue.order_queue.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.checkout_basket_rule.arn
          }
        }
      }
    ]
  })
}
