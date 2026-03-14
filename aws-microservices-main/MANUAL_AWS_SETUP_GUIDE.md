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
13. Replace the entire policy with the following (this adds the EventBridge statement to your existing owner policy):

```json
{
  "Version": "2012-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__owner_statement",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::997208471343:root"
      },
      "Action": "SQS:*",
      "Resource": "arn:aws:sqs:ap-south-1:997208471343:OrderQueue"
    },
    {
            "Sid": "AllowEventBridgeToSendMessage",
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sqs:SendMessage",
            "Resource": "arn:aws:sqs:ap-south-1:997208471343:OrderQueue",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "arn:aws:events:ap-south-1:997208471343:rule/SwnEventBus/CheckoutBasketRule"
                }
            }
        }
  ]
}

```

> ⚠️ Replace `REGION` with your region (e.g., `ap-south-1`) and `ACCOUNT_ID` with your 12-digit AWS account ID (e.g., `997208471343`) in **all four** places they appear.

14. Click **Save**

> **Checkpoint:** EventBridge is now configured. When the basket Lambda publishes a `CheckoutBasket` event, it flows: EventBridge → SQS → Ordering Lambda.

---
## To start here ###



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

> ⚠️ **Important `{proxy+}` behavior:** With the proxy setup, `event.pathParameters` will contain `{ proxy: "product/1" }` instead of `{ id: "1" }`. Your Lambda code must parse `event.path` (e.g., `/product/1`) to extract the ID manually. If your Lambda checks `event.pathParameters.id`, it will be `undefined`. Instead, use:
>
> ```javascript
> const path = event.path;             // e.g., "/product/1"
> const segments = path.split("/");    // ["", "product", "1"]
> const id = segments[2];              // "1"
> ```
>
> Make sure your Lambda's routing logic uses `event.path` (not `event.resource` or `event.pathParameters.id`) to determine which operation to perform.

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

**Update a product** (name: `UpdateProduct`):
```json
{
  "httpMethod": "PUT",
  "path": "/product/PRODUCT_ID",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": "{\"price\": 899}"
}
```

**Delete a product** (name: `DeleteProduct`):
```json
{
  "httpMethod": "DELETE",
  "path": "/product/PRODUCT_ID",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": null
}
```

#### Test Basket Lambda

1. Go to **Lambda** → select `basketLambdaFunction` → **Test** tab

**Create basket** (name: `CreateBasket`):
```json
{
  "httpMethod": "POST",
  "path": "/basket",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": "{\"userName\": \"swn\", \"items\": [{\"quantity\": 2, \"color\": \"black\", \"price\": 999, \"productId\": \"1\", \"productName\": \"iPhone 15\"}]}"
}
```

**Get basket** (name: `GetBasket`):
```json
{
  "httpMethod": "GET",
  "path": "/basket/swn",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": null
}
```

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

Before running `CheckoutBasket`, you MUST first run the `CreateBasket` test event above. The checkout reads the basket from DynamoDB, so it must exist.

Verify: Go to **DynamoDB** → **Tables** → `basket` → **Explore table items** → You should see an item with `userName: "swn"`.

**Step 2 — Run the CheckoutBasket test event**

In the `basketLambdaFunction` → **Test** tab → select `CheckoutBasket` → click **Test**.

✅ **Success looks like:**
```json
{
  "statusCode": 200,
  "body": "{\"message\":\"Successfully finished operation: \\\"POST\\\"\",\"body\":{...\"FailedEntryCount\":0...}}"
}
```

❌ **If you see `basket should exist in items`:** The basket doesn't exist or has no `items` array. Run `CreateBasket` first.

**Step 3 — Verify EventBridge received the event**

Go to **EventBridge** → **Event buses** → `SwnEventBus` → **Monitoring** tab → Check `EventsMatched` metric (may take 1–2 minutes to appear).

**Step 4 — Verify SQS received the message**

Go to **SQS** → `OrderQueue`:
- Check **Messages available** — it should briefly show `1` then drop to `0` (meaning the ordering Lambda picked it up)
- If messages are **stuck at 1+**, the ordering Lambda has an error — check its CloudWatch logs

**Step 5 — Verify the order was created in DynamoDB**

Go to **DynamoDB** → **Tables** → `order` → **Explore table items** → You should see a new item with:
- `userName: "swn"`
- `orderDate: "2025-..."` (auto-generated timestamp)
- Items from the basket

**Step 6 — Verify the basket was deleted**

Go to **DynamoDB** → **Tables** → `basket` → **Explore table items** → The `swn` item should be **gone** (checkout deletes it).

**Step 7 — Verify via the Ordering Lambda**

Go to **Lambda** → `orderingLambdaFunction` → **Test** tab → Run the `GetAllOrders` test event:
```json
{
  "httpMethod": "GET",
  "path": "/order",
  "pathParameters": null,
  "queryStringParameters": null,
  "body": null
}
```
You should see the order created by the checkout.

#### Debugging Checkout Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `basket should exist in items` | No basket in DynamoDB | Run `CreateBasket` test first |
| `FailedEntryCount: 1` in response | EventBridge rejected the event | Check `EVENT_BUSNAME` env var = `SwnEventBus` |
| EventBridge `EventsMatched = 0` | Event pattern mismatch | Verify `EVENT_SOURCE` and `EVENT_DETAILTYPE` env vars match the rule pattern |
| SQS messages stuck (not consumed) | Ordering Lambda trigger issue | Check Lambda → Configuration → Triggers → SQS is enabled |
| SQS messages stuck (consumed but error) | Ordering Lambda code error | Check **CloudWatch Logs** → `/aws/lambda/orderingLambdaFunction` |
| No order in DynamoDB `order` table | Ordering Lambda permission issue | Check `OrderingLambdaRole` has DynamoDB access to `order` table |
| Order in SQS but EventBridge shows 0 | SQS access policy missing | Verify the EventBridge statement in SQS access policy (Phase 5, step 13) |

#### Troubleshooting: Basket Deleted but No Order Created

If the basket is removed but no order appears in the `order` DynamoDB table, the issue is in the **EventBridge → SQS → Ordering Lambda** chain. Debug in this order:

**Step 1 — Check EventBridge Monitoring**

1. Go to **EventBridge** → **Rules** → select `SwnEventBus` event bus → `CheckoutBasketRule`
2. Click **Monitoring** tab
3. Check these metrics:
   - **Invocations** — did the rule fire? If `0`, the event pattern doesn't match
   - **FailedInvocations** — if > 0, EventBridge can't deliver to SQS (permission issue)

**Step 2 — Check SQS for stuck messages**

1. Go to **SQS** → `OrderQueue`
2. Check **Messages Available** and **Messages in Flight**
   - If messages are **available but not consumed**: the Lambda trigger is disabled or misconfigured
   - If messages are **0**: either EventBridge didn't send them, or the ordering Lambda consumed them but failed

3. Click **Send and receive messages** → **Poll for messages** to see if any messages are stuck

**Step 3 — Check Ordering Lambda CloudWatch Logs**

1. Go to **CloudWatch** → **Log groups** → `/aws/lambda/orderingLambdaFunction`
2. Click the latest log stream
3. Look for errors. Common issues:

   **Issue A — SQS event format mismatch:**
   The ordering Lambda receives an SQS event (not an HTTP event). The `event` looks like:
   ```json
   {
     "Records": [
       {
         "body": "{\"detail\":{\"userName\":\"swn\",\"items\":[...]}}"
       }
     ]
   }
   ```
   Your ordering Lambda must parse `event.Records[0].body` to extract the order data. If it's looking for `event.httpMethod`, it will fail silently.

   **Issue B — Order data nested in `detail`:**
   EventBridge wraps your payload inside a `detail` field. So the SQS message body is:
   ```json
   {
     "version": "0",
     "source": "com.swn.basket.checkoutbasket",
     "detail-type": "CheckoutBasket",
     "detail": {
       "userName": "swn",
       "totalPrice": 999,
       "items": [...]
     }
   }
   ```
   The ordering Lambda must extract the order from `detail`, not from the root.

**Step 4 — Verify Ordering Lambda handles SQS events**

Share your `src/ordering/index.mjs` file to check if it correctly:
1. Parses `event.Records[0].body` (SQS wrapper)
2. Extracts the order from the `detail` field (EventBridge wrapper)
3. Writes to DynamoDB with both `userName` and `orderDate` (partition key + sort key)

**Step 5 — Quick manual test of Ordering Lambda**

In **Lambda** → `orderingLambdaFunction` → **Test** tab, create a test event that simulates an SQS message:

```json
{
  "Records": [
    {
      "messageId": "test-123",
      "body": "{\"version\":\"0\",\"source\":\"com.swn.basket.checkoutbasket\",\"detail-type\":\"CheckoutBasket\",\"detail\":{\"userName\":\"swn\",\"totalPrice\":999,\"firstName\":\"test\",\"lastName\":\"user\",\"email\":\"test@example.com\",\"items\":[{\"quantity\":2,\"color\":\"black\",\"price\":999,\"productId\":\"1\",\"productName\":\"iPhone 15\"}]}}"
    }
  ]
}
```

Run this test. Then check if an order appears in the `order` DynamoDB table.

- ✅ If the order appears → the issue is in EventBridge/SQS delivery (go back to Steps 1-2)
- ❌ If it fails → the ordering Lambda code has a bug (share the code for review)

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
