# AWS Serverless Microservices — Deployment Guide

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [AWS Services Used](#aws-services-used)
- [Project Structure](#project-structure)
- [Code Walkthrough](#code-walkthrough)
  - [Stack Entry Point](#stack-entry-point)
  - [Database Layer](#database-layer)
  - [Microservices (Lambda) Layer](#microservices-lambda-layer)
  - [API Gateway Layer](#api-gateway-layer)
  - [Event Bus Layer](#event-bus-layer)
  - [Queue Layer](#queue-layer)
- [API Endpoints](#api-endpoints)
- [Event-Driven Checkout Flow](#event-driven-checkout-flow)
- [Deployment Steps](#deployment-steps)
  - [Step 1 — Prerequisites](#step-1--prerequisites)
  - [Step 2 — Configure AWS Credentials](#step-2--configure-aws-credentials)
  - [Step 3 — Install Project Dependencies](#step-3--install-project-dependencies)
  - [Step 4 — Set AWS Account and Region (Optional)](#step-4--set-aws-account-and-region-optional)
  - [Step 5 — Bootstrap the CDK Environment](#step-5--bootstrap-the-cdk-environment)
  - [Step 6 — Build the TypeScript Project](#step-6--build-the-typescript-project)
  - [Step 7 — Synthesize the CloudFormation Template](#step-7--synthesize-the-cloudformation-template)
  - [Step 8 — Deploy to AWS](#step-8--deploy-to-aws)
  - [Step 9 — Verify the Deployment](#step-9--verify-the-deployment)
  - [Step 10 — Useful Ongoing Commands](#step-10--useful-ongoing-commands)
- [Important Notes and Warnings](#important-notes-and-warnings)

---

## Architecture Overview

This project implements a **serverless e-commerce backend** using AWS CDK (Cloud Development Kit) with TypeScript. It follows a **microservices architecture** with the **database-per-service** pattern.

```
Client
  │
  ▼
API Gateway (3 REST APIs)
  ├── /product   →  Product Lambda   →  DynamoDB (product table)
  ├── /basket    →  Basket Lambda    →  DynamoDB (basket table)
  │       └── POST /basket/checkout  →  EventBridge (SwnEventBus)
  │                                          │
  │                                   CheckoutBasketRule
  │                                          │
  │                                          ▼
  │                                     SQS (OrderQueue)
  │                                          │
  │                                          ▼
  └── /order     →  Ordering Lambda  →  DynamoDB (order table)
```

---

## AWS Services Used

| Service | Resource Name | Purpose |
|---------|--------------|---------|
| **AWS Lambda** | `productLambdaFunction` | Handles CRUD operations for products |
| **AWS Lambda** | `basketLambdaFunction` | Handles basket operations and checkout event publishing |
| **AWS Lambda** | `orderingLambdaFunction` | Processes orders from SQS and handles order queries |
| **Amazon DynamoDB** | `product` table | Stores product catalog data |
| **Amazon DynamoDB** | `basket` table | Stores user shopping baskets |
| **Amazon DynamoDB** | `order` table | Stores completed orders |
| **Amazon API Gateway** | Product Service API | REST API for product endpoints |
| **Amazon API Gateway** | Basket Service API | REST API for basket endpoints |
| **Amazon API Gateway** | Order Service API | REST API for order endpoints |
| **Amazon EventBridge** | `SwnEventBus` | Custom event bus for async communication |
| **Amazon SQS** | `OrderQueue` | Message queue to buffer checkout events for ordering service |
| **AWS IAM** | (auto-generated roles) | Permissions for Lambda to access DynamoDB, EventBridge, and SQS |
| **AWS CloudFormation** | `AwsMicroservicesStack` | Manages all infrastructure as code |
| **Amazon S3** | CDK bootstrap bucket | Stores bundled Lambda deployment packages |

---

## Project Structure

```
aws-microservices-main/
├── bin/
│   └── aws-microservices.ts        # CDK app entry point
├── lib/
│   ├── aws-microservices-stack.ts   # Main stack — wires all constructs together
│   ├── database.ts                  # DynamoDB table definitions
│   ├── microservice.ts              # Lambda function definitions
│   ├── apigateway.ts                # API Gateway REST API definitions
│   ├── eventbus.ts                  # EventBridge bus and rules
│   └── queue.ts                     # SQS queue definition
├── src/
│   ├── product/
│   │   ├── index.js                 # Product Lambda handler
│   │   ├── ddbClient.js             # DynamoDB client for product service
│   │   └── package.json
│   ├── basket/
│   │   ├── index.js                 # Basket Lambda handler
│   │   ├── ddbClient.js             # DynamoDB client for basket service
│   │   ├── eventBridgeClient.js     # EventBridge client for publishing events
│   │   ├── checkoutbasketevents.json # Sample checkout event payload
│   │   └── package.json
│   └── ordering/
│       ├── index.js                 # Ordering Lambda handler
│       ├── ddbClient.js             # DynamoDB client for ordering service
│       └── package.json
├── test/
│   └── aws-microservices.test.ts    # Unit tests
├── cdk.json                         # CDK configuration
├── package.json                     # Node.js dependencies
├── tsconfig.json                    # TypeScript configuration
└── jest.config.js                   # Test configuration
```

---

## Code Walkthrough

### Stack Entry Point

**File:** `bin/aws-microservices.ts`

Creates the CDK app and instantiates the main `AwsMicroservicesStack`. By default, the stack is environment-agnostic (can be deployed to any account/region).

**File:** `lib/aws-microservices-stack.ts`

The **main stack** that orchestrates all constructs in the correct dependency order:

1. **Database** — Creates 3 DynamoDB tables
2. **Microservices** — Creates 3 Lambda functions (receives table references)
3. **API Gateway** — Creates 3 REST APIs (receives Lambda function references)
4. **Queue** — Creates an SQS queue (receives ordering Lambda as consumer)
5. **EventBus** — Creates EventBridge bus and rules (receives basket Lambda as publisher and SQS queue as target)

---

### Database Layer

**File:** `lib/database.ts` — `SwnDatabase` construct

Creates three DynamoDB tables, all configured with:
- **PAY_PER_REQUEST** billing (no capacity planning needed)
- **RemovalPolicy.DESTROY** (tables are deleted when stack is destroyed)

| Table | Partition Key | Sort Key | Schema |
|-------|-------------|----------|--------|
| `product` | `id` (String) | — | name, description, imageFile, price, category |
| `basket` | `userName` (String) | — | items (array of maps: quantity, color, price, productId, productName) |
| `order` | `userName` (String) | `orderDate` (String) | totalPrice, firstName, lastName, email, address, paymentMethod, cardInfo |

---

### Microservices (Lambda) Layer

**File:** `lib/microservice.ts` — `SwnMicroservices` construct

Creates three Node.js Lambda functions with the following configuration:

| Function | Handler | Runtime | Environment Variables | IAM Permissions |
|----------|---------|---------|----------------------|-----------------|
| `productLambdaFunction` | `src/product/index.js` | Node.js 14.x | `PRIMARY_KEY=id`, `DYNAMODB_TABLE_NAME=product` | DynamoDB read/write on product table |
| `basketLambdaFunction` | `src/basket/index.js` | Node.js 14.x | `PRIMARY_KEY=userName`, `DYNAMODB_TABLE_NAME=basket`, `EVENT_SOURCE`, `EVENT_DETAILTYPE`, `EVENT_BUSNAME` | DynamoDB read/write on basket table |
| `orderingLambdaFunction` | `src/ordering/index.js` | Node.js 14.x | `PRIMARY_KEY=userName`, `SORT_KEY=orderDate`, `DYNAMODB_TABLE_NAME=order` | DynamoDB read/write on order table |

All functions exclude `aws-sdk` from bundling since it is available in the Lambda runtime.

---

### API Gateway Layer

**File:** `lib/apigateway.ts` — `SwnApiGateway` construct

Creates three separate REST APIs (one per microservice) with `proxy: false` (explicit route definitions).

#### Product Service API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/product` | List all products |
| `POST` | `/product` | Create a new product |
| `GET` | `/product/{id}` | Get a single product by ID |
| `PUT` | `/product/{id}` | Update a product by ID |
| `DELETE` | `/product/{id}` | Delete a product by ID |

#### Basket Service API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/basket` | List all baskets |
| `POST` | `/basket` | Create/update a basket |
| `GET` | `/basket/{userName}` | Get a user's basket |
| `DELETE` | `/basket/{userName}` | Delete a user's basket |
| `POST` | `/basket/checkout` | Checkout basket (triggers async order flow) |

#### Order Service API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/order` | List all orders |
| `GET` | `/order/{userName}` | Get orders for a user (supports `?orderDate=` query param) |

---

### Event Bus Layer

**File:** `lib/eventbus.ts` — `SwnEventBus` construct

Creates an **Amazon EventBridge** custom event bus named `SwnEventBus` with:

- **Rule:** `CheckoutBasketRule`
  - **Source pattern:** `com.swn.basket.checkoutbasket`
  - **Detail type:** `CheckoutBasket`
  - **Target:** SQS `OrderQueue`
- **Permission:** Grants `PutEvents` permission to the basket Lambda function

---

### Queue Layer

**File:** `lib/queue.ts` — `SwnQueue` construct

Creates an **Amazon SQS** queue named `OrderQueue`:
- **Visibility timeout:** 30 seconds
- **Event source mapping:** Ordering Lambda consumes messages with `batchSize: 1`

---

## API Endpoints

After deployment, three API Gateway endpoints are created. Example format:

```
https://<api-id>.execute-api.<region>.amazonaws.com/prod/product
https://<api-id>.execute-api.<region>.amazonaws.com/prod/basket
https://<api-id>.execute-api.<region>.amazonaws.com/prod/order
```

The actual URLs are printed as CloudFormation outputs after `cdk deploy`.

---

## Event-Driven Checkout Flow

The checkout process follows an **asynchronous event-driven pattern**:

```
1. Client sends POST /basket/checkout { userName: "swn" }
         │
         ▼
2. Basket Lambda retrieves user's basket from DynamoDB
         │
         ▼
3. Basket Lambda publishes event to EventBridge (SwnEventBus)
   Event source:  "com.swn.basket.checkoutbasket"
   Detail type:   "CheckoutBasket"
   Detail:        { full basket + checkout info }
         │
         ▼
4. EventBridge matches CheckoutBasketRule
         │
         ▼
5. Event is forwarded to SQS OrderQueue
         │
         ▼
6. Ordering Lambda is triggered (SQS event source, batch size 1)
         │
         ▼
7. Ordering Lambda writes order record to DynamoDB order table
```

This decouples the basket service from the ordering service, providing:
- **Resilience** — If the ordering service is down, messages queue up in SQS
- **Scalability** — Each service scales independently
- **Loose coupling** — Services communicate via events, not direct calls

---

## Deployment Steps

### Step 1 — Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| AWS Account | — | To host all resources |
| AWS CLI | v2+ | Interact with AWS from terminal |
| Node.js | ≥ 14.x | Runtime for Lambda & CDK |
| npm | ≥ 6.x | Package manager |
| AWS CDK CLI | ≥ 2.17.0 | Infrastructure-as-code deployment |

Install AWS CLI:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

Install AWS CDK globally:

```bash
npm install -g aws-cdk
```

Verify installations:

```bash
aws --version
cdk --version
node --version
```

---

### Step 2 — Configure AWS Credentials

```bash
aws configure
```

Provide:

| Prompt | Example |
|--------|---------|
| AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| Default region name | `us-east-1` |
| Default output format | `json` |

> **Required IAM permissions:** Lambda, API Gateway, DynamoDB, EventBridge, SQS, S3, CloudFormation, IAM (role creation). Using the `AdministratorAccess` managed policy is simplest for development.

---

### Step 3 — Install Project Dependencies

```bash
cd /path/to/aws-microservices-main
npm install
```

This installs all dependencies listed in `package.json`:
- `aws-cdk-lib` (v2.17.0)
- `constructs` (v10.x)
- `typescript`, `ts-node`, and testing libraries

---

### Step 4 — Set AWS Account and Region (Optional)

Edit `bin/aws-microservices.ts` and uncomment one of the `env` options:

**Option A — Dynamic (reads from CLI configuration):**

```typescript
env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
```

**Option B — Explicit:**

```typescript
env: { account: '123456789012', region: 'us-east-1' },
```

---

### Step 5 — Bootstrap the CDK Environment

CDK requires a one-time bootstrap per account/region combination:

```bash
cdk bootstrap aws://ACCOUNT_ID/REGION
```

Example:

```bash
cdk bootstrap aws://123456789012/us-east-1
```

This creates a `CDKToolkit` CloudFormation stack containing:
- An S3 bucket for Lambda deployment packages
- IAM roles for CloudFormation deployments

---

### Step 6 — Build the TypeScript Project

```bash
npm run build
```

Compiles all `.ts` files in `lib/` and `bin/` to JavaScript.

---

### Step 7 — Synthesize the CloudFormation Template

```bash
cdk synth
```

Generates a CloudFormation template in `cdk.out/`. Review it to verify all expected resources.

**Expected resources (12+):**

| Count | Resource Type |
|-------|--------------|
| 3 | DynamoDB Tables |
| 3 | Lambda Functions |
| 3 | API Gateway REST APIs |
| 1 | EventBridge Custom Event Bus |
| 1 | EventBridge Rule |
| 1 | SQS Queue |
| 3+ | IAM Roles & Policies |

---

### Step 8 — Deploy to AWS

```bash
cdk deploy
```

CDK will:

1. **Bundle** each Lambda function's source code using esbuild
2. **Upload** bundled assets to the CDK bootstrap S3 bucket
3. **Submit** the CloudFormation template
4. **Provision** all resources in the correct dependency order

> You will be prompted to approve IAM changes. Type `y` to confirm.

First deployment takes approximately **3–5 minutes**.

On success, the output displays API Gateway endpoint URLs:

```
Outputs:
AwsMicroservicesStack.ApiGatewayproductApiEndpointXXXX = https://abc123.execute-api.us-east-1.amazonaws.com/prod/
AwsMicroservicesStack.ApiGatewaybasketApiEndpointXXXX  = https://def456.execute-api.us-east-1.amazonaws.com/prod/
AwsMicroservicesStack.ApiGatewayorderApiEndpointXXXX   = https://ghi789.execute-api.us-east-1.amazonaws.com/prod/
```

---

### Step 9 — Verify the Deployment

#### Test Product API

```bash
# Create a product
curl -X POST https://<product-api-url>/prod/product \
  -H "Content-Type: application/json" \
  -d '{"id":"1","name":"iPhone","description":"Apple iPhone","price":999,"category":"Electronics"}'

# List all products
curl https://<product-api-url>/prod/product

# Get single product
curl https://<product-api-url>/prod/product/1

# Update product
curl -X PUT https://<product-api-url>/prod/product/1 \
  -H "Content-Type: application/json" \
  -d '{"price":899}'

# Delete product
curl -X DELETE https://<product-api-url>/prod/product/1
```

#### Test Basket API

```bash
# Add to basket
curl -X POST https://<basket-api-url>/prod/basket \
  -H "Content-Type: application/json" \
  -d '{"userName":"swn","items":[{"productId":"1","quantity":2,"color":"black","price":999,"productName":"iPhone"}]}'

# Get user basket
curl https://<basket-api-url>/prod/basket/swn

# Checkout (triggers EventBridge → SQS → Ordering)
curl -X POST https://<basket-api-url>/prod/basket/checkout \
  -H "Content-Type: application/json" \
  -d '{"userName":"swn"}'

# Delete basket
curl -X DELETE https://<basket-api-url>/prod/basket/swn
```

#### Test Order API

```bash
# Get all orders
curl https://<order-api-url>/prod/order

# Get orders for a specific user
curl https://<order-api-url>/prod/order/swn

# Get orders with date filter
curl "https://<order-api-url>/prod/order/swn?orderDate=2026-03-06"
```

#### Verify in AWS Console

- **CloudFormation** → Stacks → `AwsMicroservicesStack` → Resources tab
- **Lambda** → Functions → Three functions listed
- **DynamoDB** → Tables → `product`, `basket`, `order`
- **API Gateway** → APIs → Three REST APIs
- **EventBridge** → Event buses → `SwnEventBus` → Rules → `CheckoutBasketRule`
- **SQS** → Queues → `OrderQueue`

---

### Step 10 — Useful Ongoing Commands

| Command | Purpose |
|---------|---------|
| `cdk diff` | Preview infrastructure changes before deploying |
| `cdk deploy` | Deploy changes to AWS |
| `cdk deploy --hotswap` | Fast-deploy Lambda code changes only (dev use) |
| `cdk watch` | Auto-deploy on file changes (dev use) |
| `cdk destroy` | Tear down all resources and delete the stack |
| `npm run build` | Compile TypeScript |
| `npm test` | Run unit tests |

---

## Important Notes and Warnings

### ⚠️ Runtime Version

The Lambda functions use `Runtime.NODEJS_14_X` which has reached **end of life**. For production deployments, upgrade to `Runtime.NODEJS_18_X` or `Runtime.NODEJS_20_X` in `lib/microservice.ts`.

### ⚠️ Removal Policy

All DynamoDB tables are configured with `RemovalPolicy.DESTROY`. Running `cdk destroy` **will permanently delete all data**. For production, change to `RemovalPolicy.RETAIN` in `lib/database.ts`.

### ⚠️ No Authentication

The API Gateway endpoints are **publicly accessible** with no authentication. For production, add:
- IAM Authorization
- Amazon Cognito User Pools
- API Keys with Usage Plans

### ⚠️ Cost

All resources use on-demand/pay-per-use pricing:
- **Lambda** — 1M free requests/month
- **DynamoDB** — 25 GB free storage, 25 WCU/RCU
- **API Gateway** — 1M free API calls/month (first 12 months)
- **SQS** — 1M free requests/month
- **EventBridge** — Free for AWS default events; custom events charged per million

With low traffic, this architecture stays well within the **AWS Free Tier**.

### ⚠️ CORS

No CORS configuration is set on the API Gateway. If calling from a browser frontend, you'll need to enable CORS on each API resource.

---

## License

See [LICENSE](./LICENSE) for details.
