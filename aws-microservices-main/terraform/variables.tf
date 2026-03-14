variable "aws_region" {
  description = "The AWS region to create resources in."
  default     = "us-east-1"
}

variable "product_table_name" {
  description = "The name of the DynamoDB table for products."
  default     = "product"
}

variable "basket_table_name" {
  description = "The name of the DynamoDB table for baskets."
  default     = "basket"
}

variable "order_table_name" {
  description = "The name of the DynamoDB table for orders."
  default     = "order"
}

variable "order_queue_name" {
  description = "The name of the SQS queue for orders."
  default     = "OrderQueue"
}

variable "event_bus_name" {
  description = "The name of the EventBridge event bus."
  default     = "SwnEventBus"
}
