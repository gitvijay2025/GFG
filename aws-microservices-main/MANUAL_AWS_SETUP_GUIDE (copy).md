# Manual AWS Setup Guide — Serverless E-Commerce Microservices

This guide walks through creating **every AWS resource manually** via the AWS Management Console, without using CDK or CloudFormation.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Summary](#architecture-summary)
- [Resource Creation Order](#resource-creation-order)
- [Phase 1 — Create DynamoDB Tables](#phase-1--create-dynamodb-tables)
  - [1.1 Create the Product Table](#11-create-the-product-table)
  - [1.2 Create the Basket Table](#12-create-the-basket-table)
  - [1.3 Create the Order Table](#13-create-the-order-table)
- [Phase 2 — Create IAM Roles for Lambda Functions](#phase-2--create-iam-roles-for-lambda-functions)
  - [2.1 Create the Product Lambda IAM Role](#21-create-the-product-lambda-iam-role)
  - [2.2 Create the Basket Lambda IAM Role](#22-create-the-basket-lambda-iam-role)
  - [2.3 Create the Ordering Lambda IAM Role](#23-create-the-ordering-lambda-iam-role)
- [Phase 3 — Create SQS Queue](#phase-3--create-sqs-queue)
  - [3.1 Create the Order Queue](#31-create-the-order-queue)
- [Phase 4 — Create Lambda Functions](#phase-4--create-lambda-functions)
  - [4.1 Prepare Lambda Deployment Packages](#41-prepare-lambda-deployment-packages)
  - [4.2 Create the Product Lambda Function](#42-create-the-product-lambda-function)
  - [4.3 Create the Basket Lambda Function](#43-create-the-basket-lambda-function)
  - [4.4 Create the Ordering Lambda Function](#44-create-the-ordering-lambda-function)
  - [4.5 Connect the Ordering Lambda to SQS (Event Source Mapping)](#45-connect-the-ordering-lambda-to-sqs-event-source-mapping)
- [Phase 5 — Create EventBridge Event Bus and Rule](#phase-5--create-eventbridge-event-bus-and-rule)
  - [5.1 Create the Custom Event Bus](#51-create-the-custom-event-bus)
  - [5.2 Create the Checkout Basket Rule](#52-create-the-checkout-basket-rule)
- [Phase 6 — Create API Gateway REST APIs](#phase-6--create-api-gateway-rest-apis)
  - [6.1 Create the Product Service API](#61-create-the-product-service-api)
  - [6.2 Create the Basket Service API](#62-create-the-basket-service-api)
  - [6.3 Create the Order Service API](#63-create-the-order-service-api)
  - [6.4 Deploy All APIs](#64-deploy-all-apis)
- [Phase 7 — Testing](#phase-7--testing)
- [Phase 8 — Cleanup (Delete All Resources)](#phase-8--cleanup-delete-all-resources)

---

## Prerequisites

1. An **AWS Account** with admin access
2. A web browser to access the [AWS Management Console](https://console.aws.amazon.com)
3. Choose a **region** (e.g., `us-east-1`) and use the **same region** for every resource
4. The Lambda source code from the `src/` folder of this project, zipped for upload

---

## Architecture Summary

```
Client
  │
  ▼
API Gateway (3 REST APIs)
  ├── Product Service  →  Product Lambda   →  DynamoDB (product)
  ├── Basket Service   →  Basket Lambda    →  DynamoDB (basket)
  │                           │
  │                     EventBridge (SwnEventBus)
  │                           │
  │                     SQS (OrderQueue)
  │                           │
  └── Order Service    →  Ordering Lambda  →  DynamoDB (order)
```

---

## Resource Creation Order

Resources must be created in this order to satisfy dependencies:

| Phase | Resources | Depends On |
|-------|-----------|------------|
| 1 | DynamoDB Tables (3) | Nothing |
| 2 | IAM Roles (3) | DynamoDB table ARNs, SQS ARN |
| 3 | SQS Queue (1) | Nothing |
| 4 | Lambda Functions (3) | IAM Roles, DynamoDB Tables, SQS Queue |
| 5 | EventBridge Bus + Rule (1+1) | SQS Queue, Basket Lambda |
| 6 | API Gateway REST APIs (3) | Lambda Functions |

---

## Phase 1 — Create DynamoDB Tables

### 1.1 Create the Product Table

1. Open the **AWS Console** → search for **DynamoDB** → click **DynamoDB**
2. In the left sidebar, click **Tables**
3. Click **Create table**
4. Fill in the form:

   | Field | Value |
   |-------|-------|
   | Table name | `product` |
   | Partition key | `id` (String) |
   | Sort key | *(leave empty)* |

5. Under **Table settings**, select **Customize settings**
6. Under **Read/write capacity settings**, select **On-demand**
7. Leave all other settings as default
8. Click **Create table**
9. Wait until the table status shows **Active**

---

### 1.2 Create the Basket Table

1. Go to **DynamoDB** → **Tables** → **Create table**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | Table name | `basket` |
   | Partition key | `userName` (String) |
   | Sort key | *(leave empty)* |

3. Select **Customize settings** → **On-demand** capacity
4. Click **Create table**
5. Wait until **Active**

---

### 1.3 Create the Order Table

1. Go to **DynamoDB** → **Tables** → **Create table**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | Table name | `order` |
   | Partition key | `userName` (String) |
   | Sort key | `orderDate` (String) |

3. Select **Customize settings** → **On-demand** capacity
4. Click **Create table**
5. Wait until **Active**

> **Checkpoint:** You should now have 3 tables: `product`, `basket`, `order` — all Active with On-demand billing.

---

## Phase 2 — Create IAM Roles for Lambda Functions

Each Lambda function needs an IAM execution role with specific permissions.

### 2.1 Create the Product Lambda IAM Role

1. Open the **AWS Console** → search for **IAM** → click **IAM**
2. In the left sidebar, click **Roles** → **Create role**
3. **Trusted entity type:** Select **AWS service**
4. **Use case:** Select **Lambda** → click **Next**
5. **Add permissions** — search for and select these managed policies:
   - `AWSLambdaBasicExecutionRole` (for CloudWatch Logs)
6. Click **Next**
7. **Role name:** `ProductLambdaRole`
8. Click **Create role**
9. After creation, click on `ProductLambdaRole` to open it
10. Go to the **Permissions** tab → **Add permissions** → **Create inline policy**
11. Click the **JSON** tab and paste:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/product"
        }
    ]
}
```

> ⚠️ Replace `REGION` with your region (e.g., `us-east-1`) and `ACCOUNT_ID` with your 12-digit AWS account ID.

12. Click **Next** → Policy name: `ProductDynamoDBAccess` → **Create policy**

---

### 2.2 Create the Basket Lambda IAM Role

1. Go to **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **Lambda** → **Next**
3. Add managed policy: `AWSLambdaBasicExecutionRole` → **Next**
4. **Role name:** `BasketLambdaRole` → **Create role**
5. Open `BasketLambdaRole` → **Permissions** → **Add permissions** → **Create inline policy**
6. Paste this JSON (combines DynamoDB + EventBridge permissions):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DynamoDBAccess",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/basket"
        },
        {
            "Sid": "EventBridgeAccess",
            "Effect": "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": "arn:aws:events:REGION:ACCOUNT_ID:event-bus/SwnEventBus"
        }
    ]
}
```

> ⚠️ Replace `REGION` and `ACCOUNT_ID` in both resource ARNs.

7. Policy name: `BasketDynamoDBAndEventBridgeAccess` → **Create policy**

---

### 2.3 Create the Ordering Lambda IAM Role

1. Go to **IAM** → **Roles** → **Create role**
2. **Trusted entity:** AWS service → **Lambda** → **Next**
3. Add managed policies:
   - `AWSLambdaBasicExecutionRole`
   - `AWSLambdaSQSQueueExecutionRole` (allows reading from SQS)
4. Click **Next** → **Role name:** `OrderingLambdaRole` → **Create role**
5. Open `OrderingLambdaRole` → **Permissions** → **Add permissions** → **Create inline policy**
6. Paste this JSON:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": "arn:aws:dynamodb:REGION:ACCOUNT_ID:table/order"
        }
    ]
}
```

7. Policy name: `OrderDynamoDBAccess` → **Create policy**

> **Checkpoint:** You should now have 3 IAM roles: `ProductLambdaRole`, `BasketLambdaRole`, `OrderingLambdaRole`.

---

## Phase 3 — Create SQS Queue

### 3.1 Create the Order Queue

1. Open the **AWS Console** → search for **SQS** → click **Simple Queue Service**
2. Click **Create queue**
3. Fill in:

   | Field | Value |
   |-------|-------|
   | Type | **Standard** |
   | Name | `OrderQueue` |
   | Visibility timeout | `30` seconds |
   | Message retention period | `4` days (default) |
   | Maximum message size | `256` KB (default) |
   | Delivery delay | `0` seconds (default) |
   | Receive message wait time | `0` seconds (default) |

4. Under **Access policy**, choose **Basic**
   - Select **Only the queue owner**
5. Leave all other settings as default
6. Click **Create queue**
7. **Copy the Queue ARN** — you'll need it in Phase 5 (looks like `arn:aws:sqs:REGION:ACCOUNT_ID:OrderQueue`)

> **Checkpoint:** You now have an SQS queue named `OrderQueue`.

---

## Phase 4 — Create Lambda Functions

### 4.1 Prepare Lambda Deployment Packages

On your local machine, create a ZIP file for each Lambda function:

**Product Lambda:**

```bash
cd src/product
npm install
zip -r ../../product-lambda.zip .
cd ../..
```

**Basket Lambda:**

```bash
cd src/basket
npm install
zip -r ../../basket-lambda.zip .
cd ../..
```

**Ordering Lambda:**

```bash
cd src/ordering
npm install
zip -r ../../ordering-lambda.zip .
cd ../..
```

You should now have 3 ZIP files: `product-lambda.zip`, `basket-lambda.zip`, `ordering-lambda.zip`.

---

## ===============  Will do it tomorrow from here 

### 4.2 Create the Product Lambda Function

1. Open the **AWS Console** → search for **Lambda** → click **Lambda**
2. Click **Create function**
3. Select **Author from scratch**
4. Fill in:

   | Field | Value |
   |-------|-------|
   | Function name | `productLambdaFunction` |
   | Runtime | **Node.js 18.x** (or latest available) |
   | Architecture | **x86_64** |

5. Under **Permissions**, expand **Change default execution role**
   - Select **Use an existing role**
   - Choose `ProductLambdaRole`
6. Click **Create function**
7. In the function's **Code** tab:
   - Click **Upload from** → **.zip file**
   - Upload `product-lambda.zip`
   - Click **Save**
8. Verify the **Handler** is set to `index.handler`
   - Go to **Runtime settings** → **Edit** → Handler: `index.handler` → **Save**
9. Go to the **Configuration** tab → **Environment variables** → **Edit**
10. Add these environment variables:

    | Key | Value |
    |-----|-------|
    | `PRIMARY_KEY` | `id` |
    | `DYNAMODB_TABLE_NAME` | `product` |

11. Click **Save**

---

### 4.3 Create the Basket Lambda Function

1. Go to **Lambda** → **Create function** → **Author from scratch**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | Function name | `basketLambdaFunction` |
   | Runtime | **Node.js 18.x** |
   | Architecture | **x86_64** |

3. Under **Permissions** → **Use an existing role** → select `BasketLambdaRole`
4. Click **Create function**
5. Upload `basket-lambda.zip` via **Code** → **Upload from** → **.zip file**
6. Verify Handler: `index.handler`
7. Go to **Configuration** → **Environment variables** → **Edit**
8. Add these environment variables:

   | Key | Value |
   |-----|-------|
   | `PRIMARY_KEY` | `userName` |
   | `DYNAMODB_TABLE_NAME` | `basket` |
   | `EVENT_SOURCE` | `com.swn.basket.checkoutbasket` |
   | `EVENT_DETAILTYPE` | `CheckoutBasket` |
   | `EVENT_BUSNAME` | `SwnEventBus` |

> ⚠️ **All 5 environment variables are required.** If `EVENT_SOURCE`, `EVENT_DETAILTYPE`, or `EVENT_BUSNAME` are missing, the checkout will appear to succeed (basket gets deleted) but **no order will be created** because the EventBridge event won't match the rule pattern.

9. Click **Save**

---

### 4.4 Create the Ordering Lambda Function

1. Go to **Lambda** → **Create function** → **Author from scratch**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | Function name | `orderingLambdaFunction` |
   | Runtime | **Node.js 18.x** |
   | Architecture | **x86_64** |

3. Under **Permissions** → **Use an existing role** → select `OrderingLambdaRole`
4. Click **Create function**
5. Upload `ordering-lambda.zip` via **Code** → **Upload from** → **.zip file**
6. Verify Handler: `index.handler`
7. Go to **Configuration** → **Environment variables** → **Edit**
8. Add these environment variables:

   | Key | Value |
   |-----|-------|
   | `PRIMARY_KEY` | `userName` |
   | `SORT_KEY` | `orderDate` |
   | `DYNAMODB_TABLE_NAME` | `order` |

9. Click **Save**

---

### 4.5 Connect the Ordering Lambda to SQS (Event Source Mapping)

1. Open the `orderingLambdaFunction` in the Lambda console
2. Go to the **Configuration** tab → **Triggers** → **Add trigger**
3. Select **SQS** from the dropdown
4. Fill in:

   | Field | Value |
   |-------|-------|
   | SQS queue | Select `OrderQueue` |
   | Batch size | `1` |
   | Batch window | `0` (default) |
   | Enabled | ✅ Yes |

5. Click **Add**

> **Checkpoint:** You now have 3 Lambda functions. The ordering Lambda is triggered by the SQS OrderQueue.

---

## Phase 5 — Create EventBridge Event Bus and Rule

### 5.1 Create the Custom Event Bus

1. Open the **AWS Console** → search for **EventBridge** → click **Amazon EventBridge**
2. In the left sidebar, click **Event buses**
3. Click **Create event bus**
4. Fill in:

   | Field | Value |
   |-------|-------|
   | Name | `SwnEventBus` |

5. Leave resource policy blank (default)
6. Click **Create**

---

### 5.2 Create the Checkout Basket Rule

1. In EventBridge, go to **Rules** in the left sidebar
2. Select **Event bus:** `SwnEventBus` from the dropdown
3. Click **Create rule**
4. **Step 1 — Define rule detail:**

   | Field | Value |
   |-------|-------|
   | Name | `CheckoutBasketRule` |
   | Description | `When Basket microservice checkout the basket` |
   | Event bus | `SwnEventBus` |
   | Rule type | **Rule with an event pattern** |

5. Click **Next**

6. **Step 2 — Build event pattern:**
   - Under **Event source**, select **Other**
   - Under **Event pattern**, click **Custom pattern (JSON editor)** and paste:

   ```json
   {
       "source": ["com.swn.basket.checkoutbasket"],
       "detail-type": ["CheckoutBasket"]
   }
   ```

7. Click **Next**

8. **Step 3 — Select target(s):**

   | Field | Value |
   |-------|-------|
   | Target type | **AWS service** |
   | Select a target | **SQS queue** |
   | Queue | Select `OrderQueue` |

9. Click **Next**

10. **Step 4 — Configure tags:** Skip → **Next**

11. **Step 5 — Review and create:** → **Create rule**

> **Important:** EventBridge needs permission to send messages to the SQS queue. If not auto-configured, you need to update the SQS access policy:

12. Go to **SQS** → select `OrderQueue` → **Access policy** tab → **Edit**
13. Add this statement to the policy:

```json
{
    "Sid": "AllowEventBridgeToSendMessage",
    "Effect": "Allow",
    "Principal": {
        "Service": "events.amazonaws.com"
    },
    "Action": "sqs:SendMessage",
    "Resource": "arn:aws:sqs:REGION:ACCOUNT_ID:OrderQueue",
    "Condition": {
        "ArnEquals": {
            "aws:SourceArn": "arn:aws:events:REGION:ACCOUNT_ID:rule/SwnEventBus/CheckoutBasketRule"
        }
    }
}
```

> ⚠️ Replace `REGION` and `ACCOUNT_ID` with your values.

14. Click **Save**

> **Checkpoint:** EventBridge is now configured. When the basket Lambda publishes a `CheckoutBasket` event, it flows: EventBridge → SQS → Ordering Lambda.

---

## Phase 6 — Create API Gateway REST APIs

> **💡 Why this is dynamic:** Your Lambda functions already contain routing logic — they inspect `event.httpMethod`, `event.path`, and `event.pathParameters` to decide what to do. This means API Gateway doesn't need to define every route individually. Instead, we use a **`{proxy+}` greedy path resource** that catches ALL requests and forwards them to the Lambda. **Any new routes you add to your Lambda code will work automatically without changing API Gateway.**

### 6.1 Create the Product Service API (Dynamic Proxy)

1. Open the **AWS Console** → search for **API Gateway** → click **API Gateway**
2. Under **REST API** (not HTTP API), click **Build**
3. Select **New API**
4. Fill in:

   | Field | Value |
   |-------|-------|
   | API name | `Product Service` |
   | Description | `Product microservice REST API` |
   | Endpoint Type | **Regional** |

5. Click **Create API**

#### Create the proxy resource (catches ALL routes dynamically)

6. In the **Resources** panel, select the root `/`
7. Click **Create Resource**

   | Field | Value |
   |-------|-------|
   | Resource Path | `{proxy+}` |
   | Proxy resource | ✅ **Enable** |

8. Click **Create Resource**

#### Configure the proxy integration

9. Select the `/{proxy+}` resource → **ANY** method will be auto-created
10. Configure the integration:

    | Field | Value |
    |-------|-------|
    | Integration type | **Lambda Function** |
    | Lambda Proxy Integration | ✅ **Enable** |
    | Lambda Function | Select `productLambdaFunction` |

11. Click **Save**
12. When prompted to give API Gateway permission to invoke the Lambda, click **OK**

#### Add a root method (for `/product` without trailing path)

13. Select the root `/` → **Create Method**

    | Field | Value |
    |-------|-------|
    | Method type | **ANY** |
    | Integration type | **Lambda Function** |
    | Lambda Proxy Integration | ✅ **Enable** |
    | Lambda Function | `productLambdaFunction` |

14. Click **Create Method** → **OK**

**That's it! The Lambda handles all routing internally:**

```
/
├── ANY    → productLambdaFunction (root fallback)
└── /{proxy+}
    └── ANY → productLambdaFunction (catches ALL paths & methods)
```

> This single proxy resource replaces the need to manually create `/product`, `/product/{id}`, and every GET/POST/PUT/DELETE method. The Lambda's `switch(event.httpMethod)` and `event.pathParameters` handle the routing.

---

### 6.2 Create the Basket Service API (Dynamic Proxy)

1. Go to **API Gateway** → **Create API** → **REST API** → **Build**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | API name | `Basket Service` |
   | Endpoint Type | **Regional** |

3. Click **Create API**

#### Create the proxy resource

4. Select `/` → **Create Resource**

   | Field | Value |
   |-------|-------|
   | Resource Path | `{proxy+}` |
   | Proxy resource | ✅ **Enable** |

5. Click **Create Resource**
6. Configure the `ANY` method on `/{proxy+}`:

   | Field | Value |
   |-------|-------|
   | Integration type | **Lambda Function** |
   | Lambda Proxy Integration | ✅ **Enable** |
   | Lambda Function | `basketLambdaFunction` |

7. Click **Save** → **OK**
8. Select root `/` → **Create Method** → **ANY** → Lambda: `basketLambdaFunction`, Proxy: ✅ → **Save**

**The Lambda dynamically handles all basket routes:**

```
Incoming request                    →  Lambda routing logic
GET  /basket                        →  getAllBaskets()
POST /basket                        →  createBasket()
GET  /basket/{userName}             →  getBasket(userName)
DELETE /basket/{userName}           →  deleteBasket(userName)
POST /basket/checkout               →  checkoutBasket()
```

---

### 6.3 Create the Order Service API (Dynamic Proxy)

1. Go to **API Gateway** → **Create API** → **REST API** → **Build**
2. Fill in:

   | Field | Value |
   |-------|-------|
   | API name | `Order Service` |
   | Endpoint Type | **Regional** |

3. Click **Create API**

#### Create the proxy resource

4. Select `/` → **Create Resource**

   | Field | Value |
   |-------|-------|
   | Resource Path | `{proxy+}` |
   | Proxy resource | ✅ **Enable** |

5. Click **Create Resource**
6. Configure the `ANY` method on `/{proxy+}`:

   | Field | Value |
   |-------|-------|
   | Integration type | **Lambda Function** |
   | Lambda Proxy Integration | ✅ **Enable** |
   | Lambda Function | `orderingLambdaFunction` |

7. Click **Save** → **OK**
8. Select root `/` → **Create Method** → **ANY** → Lambda: `orderingLambdaFunction`, Proxy: ✅ → **Save**

**The Lambda dynamically handles all order routes:**

```
Incoming request                             →  Lambda routing logic
GET  /order                                  →  getAllOrders()
GET  /order/{userName}                       →  getOrder(userName)
GET  /order/{userName}?orderDate=2026-03-06  →  getOrder(userName) with date filter
```

---

> ### 🔑 Key Benefit: Dynamic Routing
>
> With the `{proxy+}` approach, **your Lambda code IS the router**. If you add a new endpoint (e.g., `PUT /order/{userName}`), you only update the Lambda code — **no API Gateway changes needed**. Compare:
>
> | Approach | Resources to create per API | What happens when you add a route? |
> |----------|---------------------------|-----------------------------------|
> | **Manual (individual resources)** | 1 resource + 1 method per route (~5-10 per API) | Must add new resource + method in API Gateway |
> | **Dynamic (`{proxy+}` proxy)** | 1 proxy resource + 1 root method (always just 2) | Just update Lambda code — done! |

---

### 6.4 Deploy All APIs

You must deploy each API to make it accessible. Repeat for all 3 APIs:

1. Open the API in the API Gateway console
2. Click **Deploy API**
3. Fill in:

   | Field | Value |
   |-------|-------|
   | Deployment stage | **[New Stage]** |
   | Stage name | `prod` |

4. Click **Deploy**
5. **Copy the Invoke URL** displayed at the top — this is your API endpoint

   Format: `https://<api-id>.execute-api.<region>.amazonaws.com/prod`

Repeat for all 3 APIs. You now have:

| API | Endpoint |
|-----|----------|
| Product Service | `https://xxxxx.execute-api.REGION.amazonaws.com/prod/product` |
| Basket Service | `https://yyyyy.execute-api.REGION.amazonaws.com/prod/basket` |
| Order Service | `https://zzzzz.execute-api.REGION.amazonaws.com/prod/order` |

> **Checkpoint:** All infrastructure is now created! The full architecture is live.

---

## Phase 7 — Testing

> **💡 Cost-saving tip:** You can test Lambda functions **directly from the Lambda console** without going through API Gateway. This avoids API Gateway charges. Lambda's free tier includes **1 million requests/month**.

### Test Lambda Functions Directly (Free — No API Gateway)

#### Test Product Lambda

1. Go to **Lambda** → select `productLambdaFunction` → **Test** tab
2. Create test events with these JSON payloads:

**Create a product** (name: `CreateProduct`):
```json
{
  "httpMethod": "POST",
  "path": "/product",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": "{\"name\": \"iPhone 15\", \"description\": \"Apple smartphone\", \"imageFile\": \"iphone.jpg\", \"price\": 999, \"category\": \"Electronics\"}"
}
```

**Get all products** (name: `GetAllProducts`):
```json
{
  "httpMethod": "GET",
  "path": "/product",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": null
}
```

**Get single product** (name: `GetProduct`) — replace `PRODUCT_ID` with the id from the create response:
```json
{
  "httpMethod": "GET",
  "path": "/product/PRODUCT_ID",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": null
}
```

3. Click **Test** to run each event and check the **Execution result** for the response.

---

### Test via API Gateway (Costs per request)

> ⚠️ API Gateway charges ~$3.50 per million requests. Use the Lambda console tests above for development. Only use these curl commands for final end-to-end validation.

### Test Product API

```bash
# Create a product
curl -X POST https://xxxxx.execute-api.REGION.amazonaws.com/prod/product \
  -H "Content-Type: application/json" \
  -d '{
    "id": "1",
    "name": "iPhone 15",
    "description": "Apple smartphone",
    "imageFile": "iphone.jpg",
    "price": 999,
    "category": "Electronics"
  }'

# Get all products
curl https://xxxxx.execute-api.REGION.amazonaws.com/prod/product

# Get single product
curl https://xxxxx.execute-api.REGION.amazonaws.com/prod/product/1

# Update product
curl -X PUT https://xxxxx.execute-api.REGION.amazonaws.com/prod/product/1 \
  -H "Content-Type: application/json" \
  -d '{"price": 899}'

# Delete product
curl -X DELETE https://xxxxx.execute-api.REGION.amazonaws.com/prod/product/1
```

### Test Basket API

```bash
# Add items to basket
curl -X POST https://yyyyy.execute-api.REGION.amazonaws.com/prod/basket \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "swn",
    "items": [
      {
        "quantity": 2,
        "color": "black",
        "price": 999,
        "productId": "1",
        "productName": "iPhone 15"
      }
    ]
  }'

# Get basket for user
curl https://yyyyy.execute-api.REGION.amazonaws.com/prod/basket/swn

# Checkout basket (triggers EventBridge → SQS → Ordering Lambda)
curl -X POST https://yyyyy.execute-api.REGION.amazonaws.com/prod/basket/checkout \
  -H "Content-Type: application/json" \
  -d '{"userName": "swn"}'

# Delete basket
curl -X DELETE https://yyyyy.execute-api.REGION.amazonaws.com/prod/basket/swn
```

### Test Order API

```bash
# Get all orders
curl https://zzzzz.execute-api.REGION.amazonaws.com/prod/order

# Get orders for user
curl https://zzzzz.execute-api.REGION.amazonaws.com/prod/order/swn

# Get orders with date filter
curl "https://zzzzz.execute-api.REGION.amazonaws.com/prod/order/swn?orderDate=2026-03-06"
```

### Verify End-to-End Checkout Flow

1. Create a product via **Product API**
2. Add it to a basket via **Basket API**
3. Checkout via `POST /basket/checkout`
4. Check **SQS** console → `OrderQueue` → Messages Available should briefly spike
5. Check **DynamoDB** → `order` table → A new order record should appear
6. Query via **Order API** → `GET /order/swn`

### Debugging Tips

| Issue | Where to Check |
|-------|---------------|
| Lambda errors | **CloudWatch Logs** → Log group: `/aws/lambda/productLambdaFunction` |
| API Gateway errors | Enable **CloudWatch Logs** in API Gateway Stage settings |
| SQS messages stuck | **SQS** → `OrderQueue` → check dead-letter queue (if configured) |
| EventBridge not firing | **EventBridge** → `SwnEventBus` → **Monitoring** tab |
| Permission denied | **IAM** → Check role policies match the resource ARNs |

---

## Phase 8 — Cleanup (Delete All Resources)

Delete resources in **reverse order** to avoid dependency errors:

| Step | Service | Action |
|------|---------|--------|
| 1 | **API Gateway** | Delete all 3 APIs (Product Service, Basket Service, Order Service) |
| 2 | **EventBridge** | Delete rule `CheckoutBasketRule`, then delete event bus `SwnEventBus` |
| 3 | **Lambda** | Delete all 3 functions (remove SQS trigger from ordering first) |
| 4 | **SQS** | Delete queue `OrderQueue` |
| 5 | **DynamoDB** | Delete tables: `product`, `basket`, `order` |
| 6 | **IAM** | Delete roles: `ProductLambdaRole`, `BasketLambdaRole`, `OrderingLambdaRole` (delete inline policies first) |
| 7 | **CloudWatch Logs** | Delete log groups: `/aws/lambda/productLambdaFunction`, `/aws/lambda/basketLambdaFunction`, `/aws/lambda/orderingLambdaFunction` |

---

## Quick Reference — All Resources Created

| # | Service | Resource Name | Type |
|---|---------|--------------|------|
| 1 | DynamoDB | `product` | Table (PK: `id`) |
| 2 | DynamoDB | `basket` | Table (PK: `userName`) |
| 3 | DynamoDB | `order` | Table (PK: `userName`, SK: `orderDate`) |
| 4 | IAM | `ProductLambdaRole` | Role |
| 5 | IAM | `BasketLambdaRole` | Role |
| 6 | IAM | `OrderingLambdaRole` | Role |
| 7 | SQS | `OrderQueue` | Standard Queue |
| 8 | Lambda | `productLambdaFunction` | Function (Node.js 18.x) |
| 9 | Lambda | `basketLambdaFunction` | Function (Node.js 18.x) |
| 10 | Lambda | `orderingLambdaFunction` | Function (Node.js 18.x) |
| 11 | EventBridge | `SwnEventBus` | Custom Event Bus |
| 12 | EventBridge | `CheckoutBasketRule` | Rule |
| 13 | API Gateway | `Product Service` | REST API |
| 14 | API Gateway | `Basket Service` | REST API |
| 15 | API Gateway | `Order Service` | REST API |

**Total: 15 resources** created manually across 6 AWS services.

---

## Validation — Ensure Everything Works

### Test Checkout Basket Flow

**Checkout basket** (name: `CheckoutBasket`) — this triggers EventBridge → SQS → Ordering:
```json
{
  "httpMethod": "POST",
  "path": "/basket/checkout",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": "{\"userName\": \"swn\"}"
}
```

#### How to Validate the Checkout Flow

The checkout triggers a chain: **Basket Lambda → EventBridge → SQS → Ordering Lambda → DynamoDB**. Validate each step:

**Step 1 — Make sure a basket exists first**

Before running `CheckoutBasket`, you MUST first run the `CreateBasket` test event above. Verify: Go to **DynamoDB** → `basket` table → **Explore table items** → You should see `userName: "swn"`.

**Step 2 — Run the CheckoutBasket test event**

✅ Success: `statusCode: 200` with `FailedEntryCount: 0`

**Step 3 — Verify in DynamoDB**
- `order` table → new item with `userName: "swn"` and an `orderDate`
- `basket` table → `swn` item should be **gone**

**Step 4 — If it fails**, check:
- **CloudWatch Logs** for all 3 Lambda functions
- **SQS** → `OrderQueue` → messages stuck?
- **EventBridge** → `SwnEventBus` → Monitoring → `EventsMatched`?
