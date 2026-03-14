# Practical AWS Auto Scaling Use Cases & Step-by-Step Solutions

> **Instructions:** Review the use cases below and tell me which one(s) you'd like to implement or explore further.

---

## What is AWS Auto Scaling?

AWS Auto Scaling automatically adjusts compute capacity (EC2 instances, containers, Lambda concurrency, DynamoDB throughput, etc.) based on demand. It ensures:

- **High Availability** — enough resources to handle traffic spikes
- **Cost Optimization** — scale down during low traffic to save money
- **Performance** — maintain consistent response times under load

---

## Use Case 1: EC2 Auto Scaling Group (Classic Web Application)

**Problem:** A web application experiences unpredictable traffic — heavy during business hours, low at night. Running fixed servers wastes money or causes outages.

**Architecture:**
```
Internet → ALB (Application Load Balancer)
              ├── EC2 Instance (AZ-1a)  → Node/Express App (port 3000)
              ├── EC2 Instance (AZ-1b)  → Node/Express App (port 3000)  ← Auto Scaling Group
              └── EC2 Instance (AZ-1c)  → Node/Express App (port 3000)     (min: 2, max: 10)
```

### Your Node.js Express App Code (runs on each EC2 instance)

**app.js** — This is the application that runs on EVERY auto-scaled EC2 instance:
```javascript
import express from 'express';
import os from 'os';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { PutItemCommand, ScanCommand, QueryCommand } from '@aws-sdk/client-dynamodb';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';

const app = express();
const PORT = 3000;

const ddbClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'ap-south-1' });

app.use(express.json());

// Health check endpoint — ALB uses this to verify instance is healthy
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    hostname: os.hostname(),       // Shows WHICH instance handled this request
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// GET /products — same logic as your src/product/index.js
app.get('/products', async (req, res) => {
  try {
    console.log(`[${os.hostname()}] GET /products — handled by this instance`);

    const { Items } = await ddbClient.send(new ScanCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'product'
    }));

    res.json({
      message: 'Products fetched successfully',
      instance: os.hostname(),  // Proves auto scaling is working — different hostname each time!
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// GET /products/:id
app.get('/products/:id', async (req, res) => {
  try {
    console.log(`[${os.hostname()}] GET /products/${req.params.id}`);

    const { Items } = await ddbClient.send(new QueryCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'product',
      KeyConditionExpression: 'id = :id',
      ExpressionAttributeValues: { ':id': { S: req.params.id } }
    }));

    res.json({
      instance: os.hostname(),
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /products — create a product
app.post('/products', async (req, res) => {
  try {
    console.log(`[${os.hostname()}] POST /products`);

    const product = { ...req.body, id: crypto.randomUUID() };
    await ddbClient.send(new PutItemCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'product',
      Item: marshall(product)
    }));

    res.status(201).json({
      message: 'Product created',
      instance: os.hostname(),
      body: product
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /orders — same logic as your src/ordering/index.js
app.get('/orders', async (req, res) => {
  try {
    console.log(`[${os.hostname()}] GET /orders`);

    const { Items } = await ddbClient.send(new ScanCommand({
      TableName: process.env.ORDER_TABLE_NAME || 'order'
    }));

    res.json({
      instance: os.hostname(),
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /orders/:userName — same as your getOrder() function
app.get('/orders/:userName', async (req, res) => {
  try {
    console.log(`[${os.hostname()}] GET /orders/${req.params.userName}`);

    const params = {
      KeyConditionExpression: 'userName = :userName',
      ExpressionAttributeValues: { ':userName': { S: req.params.userName } },
      TableName: process.env.ORDER_TABLE_NAME || 'order'
    };

    if (req.query.orderDate) {
      params.KeyConditionExpression += ' and orderDate = :orderDate';
      params.ExpressionAttributeValues[':orderDate'] = { S: req.query.orderDate };
    }

    const { Items } = await ddbClient.send(new QueryCommand(params));

    res.json({
      instance: os.hostname(),
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Simulate CPU-heavy work (to trigger auto scaling)
app.get('/stress-test', (req, res) => {
  console.log(`[${os.hostname()}] Stress test started!`);
  const start = Date.now();
  // Burn CPU for 5 seconds
  while (Date.now() - start < 5000) {
    Math.sqrt(Math.random() * 999999);
  }
  res.json({
    message: 'Stress test completed — check if new instances are launching!',
    instance: os.hostname(),
    duration: '5s'
  });
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on instance ${os.hostname()} at port ${PORT}`);
  console.log(`   Health check: http://localhost:${PORT}/health`);
});
```

**package.json:**
```json
{
  "name": "auto-scaled-express-app",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node app.js",
    "dev": "node --watch app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@aws-sdk/client-dynamodb": "^3.400.0",
    "@aws-sdk/util-dynamodb": "^3.400.0"
  }
}
```

> 💡 **How to prove auto scaling works:** Hit the `/health` endpoint repeatedly — the `hostname` field will show **different instance IDs** as the ALB distributes traffic across auto-scaled instances.

**Steps:**

### Step 1: Create a Launch Template (with Node.js Express setup)
```bash
# Create user-data.sh — this runs on EVERY new instance that auto scaling launches
cat > user-data.sh << 'EOF'
#!/bin/bash
set -e

# Install Node.js 20
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git

# Clone your app (or pull from S3/CodeDeploy)
mkdir -p /opt/app
cd /opt/app

# Copy your Express app files here (from S3, CodeDeploy, or git)
aws s3 cp s3://my-app-bucket/app.zip /opt/app/app.zip
unzip app.zip

# Install dependencies and start
npm install --production

# Set environment variables
export DYNAMODB_TABLE_NAME=product
export ORDER_TABLE_NAME=order
export AWS_REGION=ap-south-1
export PORT=3000

# Run with PM2 for production (auto-restart on crash)
npm install -g pm2
pm2 start app.js --name "express-app"
pm2 startup
pm2 save
EOF

# Create the launch template
aws ec2 create-launch-template \
  --launch-template-name my-express-app-template \
  --version-description "v1-nodejs" \
  --launch-template-data '{
    "ImageId": "ami-0abcdef1234567890",
    "InstanceType": "t3.medium",
    "KeyName": "my-key-pair",
    "IamInstanceProfile": {"Name": "EC2-DynamoDB-Access-Role"},
    "SecurityGroupIds": ["sg-0123456789abcdef0"],
    "UserData": "'$(base64 -w0 user-data.sh)'"
  }'
```

### Step 2: Create an Auto Scaling Group
```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name my-web-app-asg \
  --launch-template LaunchTemplateName=my-web-app-template,Version='$Latest' \
  --min-size 2 \
  --max-size 10 \
  --desired-capacity 2 \
  --availability-zones ap-south-1a ap-south-1b ap-south-1c \
  --target-group-arns arn:aws:elasticloadbalancing:ap-south-1:123456789:targetgroup/my-tg/abc123
```

### Step 3: Create Scaling Policies

**Target Tracking Policy (recommended):**
```bash
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-web-app-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 60.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

### Step 4: Add ALB Request Count Scaling
```bash
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-web-app-asg \
  --policy-name request-count-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ALBRequestCountPerTarget",
      "ResourceLabel": "app/my-alb/abc123/targetgroup/my-tg/def456"
    },
    "TargetValue": 1000.0
  }'
```

### Step 5: Set Up CloudWatch Alarms (Auto-created by Target Tracking)
- High CPU alarm → triggers scale out
- Low CPU alarm → triggers scale in

**AWS Services:** EC2, Auto Scaling Groups, ALB, CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 1:

#### Console Step 1: Create a Launch Template
1. Go to **AWS Console** → Search **"EC2"** → Click **EC2**
2. In left sidebar → scroll to **"Instances"** → Click **"Launch Templates"**
3. Click **"Create launch template"**
4. **Launch template name and description:**
   - Name: `my-express-app-template`
   - Description: `Node.js Express app with auto scaling`
   - ✅ Check **"Provide guidance to help me set up a template that I can use with EC2 Auto Scaling"**
5. **Application and OS Images (AMI):**
   - Click **"Quick Start"** → Select **Amazon Linux 2023**
   - AMI: Amazon Linux 2023 AMI (Free tier eligible)
6. **Instance type:**
   - Select **t3.medium** (2 vCPU, 4 GB RAM)
7. **Key pair:**
   - Select your existing key pair, or click **"Create new key pair"**
8. **Network settings:**
   - Security group: Select or create one with:
     | Type | Port | Source | Purpose |
     |------|------|--------|---------|
     | HTTP | 80 | 0.0.0.0/0 | ALB traffic |
     | Custom TCP | 3000 | Security Group of ALB | Express app |
     | SSH | 22 | Your IP | SSH access |
9. **Advanced details** → Expand:
   - IAM instance profile: **EC2-DynamoDB-Access-Role** (create in IAM first if needed)
   - Scroll to **"User data"** → Paste this script:
   ```bash
   #!/bin/bash
   set -e
   curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
   yum install -y nodejs
   mkdir -p /opt/app && cd /opt/app
   aws s3 cp s3://my-app-bucket/app.zip /opt/app/app.zip
   unzip app.zip && npm install --production
   npm install -g pm2
   export DYNAMODB_TABLE_NAME=product
   export PORT=3000
   pm2 start app.js --name "express-app"
   pm2 startup && pm2 save
   ```
10. Click **"Create launch template"** ✅

#### Console Step 2: Create an Application Load Balancer (ALB)
1. Go to **EC2 Console** → Left sidebar → **"Load Balancers"**
2. Click **"Create Load Balancer"** → Choose **"Application Load Balancer"** → **"Create"**
3. **Basic configuration:**
   - Name: `my-express-alb`
   - Scheme: **Internet-facing**
   - IP address type: **IPv4**
4. **Network mapping:**
   - VPC: Select your VPC
   - Mappings: ✅ Check **at least 2 Availability Zones** (e.g., ap-south-1a, ap-south-1b)
5. **Security groups:**
   - Select/Create a security group allowing **HTTP (80)** from **0.0.0.0/0**
6. **Listeners and routing:**
   - Protocol: **HTTP**, Port: **80**
   - Click **"Create target group"** (opens new tab)
     - Target type: **Instances**
     - Name: `my-express-tg`
     - Protocol: **HTTP**, Port: **3000**
     - Health check path: `/health`
     - Advanced: Health check interval: **30s**, Healthy threshold: **2**
     - Click **"Next"** → Don't register targets yet → **"Create target group"**
   - Back in ALB tab → Select **my-express-tg**
7. Click **"Create load balancer"** ✅
8. Note the **DNS name** (e.g., `my-express-alb-123456.ap-south-1.elb.amazonaws.com`)

#### Console Step 3: Create Auto Scaling Group
1. Go to **EC2 Console** → Left sidebar → **"Auto Scaling Groups"**
2. Click **"Create Auto Scaling group"**
3. **Step 1 — Name and launch template:**
   - Name: `my-web-app-asg`
   - Launch template: **my-express-app-template**
   - Version: **Latest**
   - Click **"Next"**
4. **Step 2 — Instance launch options:**
   - VPC: Select your VPC
   - Availability Zones: ✅ Check **ap-south-1a**, **ap-south-1b**, **ap-south-1c**
   - Click **"Next"**
5. **Step 3 — Configure advanced options:**
   - Load balancing: ✅ Select **"Attach to an existing load balancer"**
   - Choose from target groups: ✅ **my-express-tg**
   - Health checks:
     - ✅ Check **"Turn on Elastic Load Balancing health checks"**
     - Health check grace period: `300` seconds
   - Click **"Next"**
6. **Step 4 — Configure group size and scaling policies:**
   - **Group size:**
     | Setting | Value |
     |---------|-------|
     | Desired capacity | `2` |
     | Minimum capacity | `2` |
     | Maximum capacity | `10` |
   - **Scaling policies:**
     - Select ✅ **"Target tracking scaling policy"**
     - Policy name: `cpu-target-tracking`
     - Metric type: **Average CPU utilization**
     - Target value: `60` (%)
     - Instance warmup: `60` seconds
   - Click **"Next"**
7. **Step 5 — Add notifications (optional):**
   - Click **"Add notification"**
   - SNS topic: Create or select a topic
   - Events: ✅ **Launch**, ✅ **Terminate**, ✅ **Fail to launch**
   - Click **"Next"**
8. **Step 6 — Add tags:**
   - Key: `Name`, Value: `express-asg-instance`
   - Key: `Project`, Value: `aws-microservices`
   - Click **"Next"**
9. **Step 7 — Review** → Click **"Create Auto Scaling group"** ✅

#### Console Step 4: Add a Second Scaling Policy (Request Count)
1. Go to **EC2** → **Auto Scaling Groups** → Click **my-web-app-asg**
2. Click **"Automatic scaling"** tab
3. Click **"Create dynamic scaling policy"**
4. Policy type: **Target tracking scaling**
5. Policy name: `request-count-tracking`
6. Metric type: **Application Load Balancer request count per target**
7. Target group: **my-express-tg**
8. Target value: `1000`
9. Click **"Create"** ✅

#### Console Step 5: Verify Auto Scaling is Working
1. Go to **EC2** → **Auto Scaling Groups** → Click **my-web-app-asg**
2. Check the **"Activity"** tab → Should show "Launching a new EC2 instance"
3. Check the **"Instance management"** tab → Should show 2 instances **InService**
4. Go to **EC2** → **Instances** → You should see 2 running instances tagged `express-asg-instance`
5. Copy the ALB DNS name → Open in browser: `http://my-express-alb-123456.elb.amazonaws.com/health`
6. You should see the JSON response with `hostname` showing the instance ID

---

## Use Case 2: DynamoDB Auto Scaling (Your Project!)

**Problem:** Your DynamoDB tables (product, basket, order) have variable read/write traffic. Fixed provisioned capacity either over-provisions (costly) or under-provisions (throttling).

**Architecture:**
```
API Gateway → Lambda → DynamoDB
                         ├── Read Capacity: 5–100 RCU (auto-scaled)
                         └── Write Capacity: 5–50 WCU (auto-scaled)
```

**Steps:**

### Step 1: Register Scalable Targets
```bash
# Register read capacity
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id "table/product" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --min-capacity 5 \
  --max-capacity 100

# Register write capacity
aws application-autoscaling register-scalable-target \
  --service-namespace dynamodb \
  --resource-id "table/product" \
  --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
  --min-capacity 5 \
  --max-capacity 50
```

### Step 2: Create Scaling Policies
```bash
# Read capacity scaling policy — target 70% utilization
aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --resource-id "table/product" \
  --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
  --policy-name "ProductReadScaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBReadCapacityUtilization"
    },
    "TargetValue": 70.0,
    "ScaleInCooldown": 60,
    "ScaleOutCooldown": 60
  }'

# Write capacity scaling policy — target 70% utilization
aws application-autoscaling put-scaling-policy \
  --service-namespace dynamodb \
  --resource-id "table/product" \
  --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
  --policy-name "ProductWriteScaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "DynamoDBWriteCapacityUtilization"
    },
    "TargetValue": 70.0,
    "ScaleInCooldown": 60,
    "ScaleOutCooldown": 60
  }'
```

### Step 3: Alternative — Use On-Demand Mode (Simplest)
```bash
aws dynamodb update-table \
  --table-name product \
  --billing-mode PAY_PER_REQUEST
```
> On-Demand mode auto-scales instantly with zero configuration, but costs ~6x more per request than well-tuned provisioned capacity.

### Terraform Example (for your project):
```hcl
resource "aws_appautoscaling_target" "dynamodb_read" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.product.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_read_policy" {
  name               = "DynamoDBReadAutoScaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_read.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_read.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_read.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
```

**AWS Services:** DynamoDB, Application Auto Scaling, CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 2:

#### Console Step 1: Enable Auto Scaling on DynamoDB Table
1. Go to **AWS Console** → Search **"DynamoDB"** → Click **DynamoDB**
2. Click **"Tables"** in the left sidebar → Click your table **"product"**
3. Click the **"Additional settings"** tab
4. Under **"Read/write capacity"** section → Click **"Edit"**
5. **Capacity mode:**
   - Select ✅ **Provisioned**
6. **Read capacity:**
   - ✅ Check **"Use auto scaling"** (toggle ON)
   - Minimum capacity units: `5`
   - Maximum capacity units: `100`
   - Target utilization (%): `70`
7. **Write capacity:**
   - ✅ Check **"Use auto scaling"** (toggle ON)
   - Minimum capacity units: `5`
   - Maximum capacity units: `50`
   - Target utilization (%): `70`
8. Click **"Save changes"** ✅

> 💡 DynamoDB will automatically create CloudWatch alarms and Application Auto Scaling policies behind the scenes.

#### Console Step 2: Verify Auto Scaling is Configured
1. Still on the **"Additional settings"** tab of your table
2. Under **"Auto Scaling"** section you should see:
   ```
   Read capacity:  Auto Scaling ON  (Min: 5, Max: 100, Target: 70%)
   Write capacity: Auto Scaling ON  (Min: 5, Max: 50, Target: 70%)
   ```
3. Click **"View in Application Auto Scaling"** to see the policies

#### Console Step 3: Switch to On-Demand Mode (Alternative — Easiest)
1. Go to **DynamoDB** → **Tables** → Click **"product"**
2. Click **"Additional settings"** tab → **"Edit"**
3. Capacity mode: Select ✅ **On-demand**
4. Click **"Save changes"** ✅

> ⚠️ On-Demand = zero config, auto-scales instantly, but costs ~6x more per request.

#### Console Step 4: Monitor in CloudWatch
1. Go to **CloudWatch Console** → **"Metrics"** → **"All metrics"**
2. Click **"DynamoDB"** → **"Table Metrics"**
3. Search for your table **"product"**
4. Select these metrics to monitor:
   - ✅ `ConsumedReadCapacityUnits`
   - ✅ `ConsumedWriteCapacityUnits`
   - ✅ `ProvisionedReadCapacityUnits`
   - ✅ `ProvisionedWriteCapacityUnits`
5. You'll see the provisioned line adjust up/down as consumed capacity changes

#### Repeat for Other Tables:
- Repeat Console Steps 1-2 for **"basket"** and **"order"** tables

---

## Use Case 3: Lambda Provisioned Concurrency Auto Scaling

**Problem:** Lambda cold starts cause latency spikes for time-sensitive APIs. You want pre-warmed instances that scale with traffic.

**Architecture:**
```
API Gateway → Lambda (Provisioned Concurrency: 5–50, auto-scaled)
                ├── 5 warm instances (baseline)
                └── up to 50 warm instances (peak)
```

**Steps:**

### Step 1: Publish a Lambda Version
```bash
aws lambda publish-version \
  --function-name orderingMicroservice \
  --description "Production v1"
```

### Step 2: Create an Alias
```bash
aws lambda create-alias \
  --function-name orderingMicroservice \
  --name prod \
  --function-version 1
```

### Step 3: Set Provisioned Concurrency
```bash
aws lambda put-provisioned-concurrency-config \
  --function-name orderingMicroservice \
  --qualifier prod \
  --provisioned-concurrent-executions 5
```

### Step 4: Register Auto Scaling Target
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace lambda \
  --resource-id "function:orderingMicroservice:prod" \
  --scalable-dimension "lambda:function:ProvisionedConcurrency" \
  --min-capacity 5 \
  --max-capacity 50
```

### Step 5: Create Target Tracking Policy
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace lambda \
  --resource-id "function:orderingMicroservice:prod" \
  --scalable-dimension "lambda:function:ProvisionedConcurrency" \
  --policy-name "LambdaConcurrencyScaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "LambdaProvisionedConcurrencyUtilization"
    },
    "TargetValue": 0.7
  }'
```

### Step 6: Scheduled Scaling (for predictable traffic patterns)
```bash
# Scale up to 30 warm instances every weekday at 8 AM
aws application-autoscaling put-scheduled-action \
  --service-namespace lambda \
  --resource-id "function:orderingMicroservice:prod" \
  --scalable-dimension "lambda:function:ProvisionedConcurrency" \
  --scheduled-action-name "morning-scale-up" \
  --schedule "cron(0 8 ? * MON-FRI *)" \
  --scalable-target-action MinCapacity=30,MaxCapacity=50

# Scale down to 5 warm instances every night at 10 PM
aws application-autoscaling put-scheduled-action \
  --service-namespace lambda \
  --resource-id "function:orderingMicroservice:prod" \
  --scalable-dimension "lambda:function:ProvisionedConcurrency" \
  --scheduled-action-name "night-scale-down" \
  --schedule "cron(0 22 ? * MON-FRI *)" \
  --scalable-target-action MinCapacity=5,MaxCapacity=10
```

**AWS Services:** Lambda, Application Auto Scaling, CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 3:

#### Console Step 1: Publish a Lambda Version
1. Go to **AWS Console** → Search **"Lambda"** → Click **Lambda**
2. Click on your function **"orderingMicroservice"**
3. Click **"Actions"** dropdown (top right) → **"Publish new version"**
4. Description: `Production v1`
5. Click **"Publish"** ✅
6. Note the **Version number** (e.g., `1`)

#### Console Step 2: Create an Alias
1. On the function page → Click **"Aliases"** tab
2. Click **"Create alias"**
3. Name: `prod`
4. Description: `Production alias`
5. Version: **1** (the version you just published)
6. Click **"Save"** ✅

#### Console Step 3: Configure Provisioned Concurrency
1. Click on the **"prod"** alias you just created
2. Click **"Configuration"** tab → **"Provisioned concurrency"**
3. Click **"Edit"**
4. Provisioned concurrency: `5`
5. Click **"Save"** ✅
6. Wait for status to change from **"In progress"** to **"Ready"** (takes 1-3 minutes)

#### Console Step 4: Enable Auto Scaling on Provisioned Concurrency
1. Still on the **"prod"** alias → **"Configuration"** → **"Provisioned concurrency"**
2. Under the provisioned concurrency section, click **"Manage auto scaling"** (or **"Configure auto scaling"**)
3. **Auto Scaling settings:**
   - ✅ Check **"Enable Application Auto Scaling"**
   - Minimum: `5`
   - Maximum: `50`
   - Target utilization: `70` (%)
4. Click **"Save"** ✅

> 💡 AWS will now automatically increase provisioned concurrency from 5→50 as utilization goes above 70%, and scale back down when traffic drops.

#### Console Step 5: Add Scheduled Scaling (Optional)
1. Go to **AWS Console** → Search **"Application Auto Scaling"**
2. Or go to **CloudWatch** → **Application Auto Scaling** (left sidebar)
3. Find the Lambda resource: `function:orderingMicroservice:prod`
4. Click **"Scheduled actions"** tab → **"Create scheduled action"**
5. **Morning scale-up:**
   - Name: `morning-scale-up`
   - Schedule: `cron(0 8 ? * MON-FRI *)`
   - Min capacity: `30`, Max capacity: `50`
   - Click **"Create"** ✅
6. **Night scale-down:**
   - Name: `night-scale-down`
   - Schedule: `cron(0 22 ? * MON-FRI *)`
   - Min capacity: `5`, Max capacity: `10`
   - Click **"Create"** ✅

#### Console Step 6: Monitor Provisioned Concurrency
1. Go to **Lambda Console** → Click **orderingMicroservice** → **"Monitor"** tab
2. Check these metrics:
   - **Provisioned Concurrency Invocations** — requests served by warm instances
   - **Provisioned Concurrency Spillover Invocations** — requests that had cold starts (overflow)
   - **Provisioned Concurrency Utilization** — should stay around 70%
3. If **Spillover** is high → increase Maximum in auto scaling settings

---

## Use Case 4: ECS Fargate Auto Scaling (Containerized Microservices)

**Problem:** Containerized microservices need to scale based on CPU, memory, or custom metrics without managing EC2 instances.

**Architecture:**
```
ALB → ECS Fargate Service
        ├── Container 1 → Express App (port 3000)
        ├── Container 2 → Express App (port 3000)  ← Service Auto Scaling
        └── Container N → Express App (port 3000)     (min: 2, max: 20)
```

### Your Node.js Express App — Dockerized for ECS Fargate

**Dockerfile:**
```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm ci --production

# Copy application code
COPY app.js ./

# Expose port
EXPOSE 3000

# Health check — ECS uses this to determine container health
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider http://localhost:3000/health || exit 1

# Start the Express app
CMD ["node", "app.js"]
```

**app.js** (with container-aware logging):
```javascript
import express from 'express';
import os from 'os';
import { DynamoDBClient, ScanCommand, QueryCommand, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';

const app = express();
const PORT = process.env.PORT || 3000;
const ddbClient = new DynamoDBClient({ region: process.env.AWS_REGION || 'ap-south-1' });

app.use(express.json());

// ECS metadata — get the Task ID to prove which container handled the request
const getTaskId = () => {
  // ECS injects this env var into Fargate containers
  const metadata = process.env.ECS_CONTAINER_METADATA_URI_V4;
  return os.hostname(); // In ECS, hostname = short task ID
};

// Health check — ALB + ECS health checks hit this
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    container: getTaskId(),
    memoryUsage: `${Math.round(process.memoryUsage().rss / 1024 / 1024)}MB`,
    cpuUsage: process.cpuUsage(),
    uptime: `${Math.round(process.uptime())}s`
  });
});

// GET /products — your product microservice logic
app.get('/products', async (req, res) => {
  try {
    console.log(`[Container: ${getTaskId()}] GET /products`);
    const { Items } = await ddbClient.send(new ScanCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'product'
    }));
    res.json({
      container: getTaskId(),  // Shows WHICH Fargate container handled this
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message, container: getTaskId() });
  }
});

// POST /products
app.post('/products', async (req, res) => {
  try {
    console.log(`[Container: ${getTaskId()}] POST /products`);
    const product = { ...req.body, id: crypto.randomUUID() };
    await ddbClient.send(new PutItemCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'product',
      Item: marshall(product)
    }));
    res.status(201).json({ container: getTaskId(), body: product });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /orders — your ordering microservice logic
app.get('/orders', async (req, res) => {
  try {
    console.log(`[Container: ${getTaskId()}] GET /orders`);
    const { Items } = await ddbClient.send(new ScanCommand({
      TableName: process.env.ORDER_TABLE_NAME || 'order'
    }));
    res.json({
      container: getTaskId(),
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /orders/:userName
app.get('/orders/:userName', async (req, res) => {
  try {
    console.log(`[Container: ${getTaskId()}] GET /orders/${req.params.userName}`);
    const { Items } = await ddbClient.send(new QueryCommand({
      TableName: process.env.ORDER_TABLE_NAME || 'order',
      KeyConditionExpression: 'userName = :userName',
      ExpressionAttributeValues: { ':userName': { S: req.params.userName } }
    }));
    res.json({
      container: getTaskId(),
      body: Items ? Items.map(item => unmarshall(item)) : []
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Stress test — generates CPU load to trigger ECS auto scaling
app.get('/stress', (req, res) => {
  const seconds = parseInt(req.query.seconds) || 5;
  console.log(`[Container: ${getTaskId()}] Stress test for ${seconds}s`);
  const start = Date.now();
  while (Date.now() - start < seconds * 1000) {
    Math.sqrt(Math.random() * 999999);
  }
  res.json({ message: `CPU burned for ${seconds}s`, container: getTaskId() });
});

app.listen(PORT, () => {
  console.log(`🐳 Container ${getTaskId()} running Express on port ${PORT}`);
});
```

**Build & Push to ECR:**
```bash
# Create ECR repository
aws ecr create-repository --repository-name my-express-app

# Build and push
docker build -t my-express-app .
docker tag my-express-app:latest 123456789.dkr.ecr.ap-south-1.amazonaws.com/my-express-app:latest
aws ecr get-login-password | docker login --username AWS --password-stdin 123456789.dkr.ecr.ap-south-1.amazonaws.com
docker push 123456789.dkr.ecr.ap-south-1.amazonaws.com/my-express-app:latest
```

> 💡 **How to prove Fargate auto scaling works:** Call `/products` or `/health` repeatedly — the `container` field in the JSON response shows **different task IDs** as ECS scales out new containers.

**Steps:**

### Step 1: Register Scalable Target
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id "service/my-cluster/my-service" \
  --scalable-dimension "ecs:service:DesiredCount" \
  --min-capacity 2 \
  --max-capacity 20
```

### Step 2: CPU-Based Scaling
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id "service/my-cluster/my-service" \
  --scalable-dimension "ecs:service:DesiredCount" \
  --policy-name "ecs-cpu-scaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "TargetValue": 60.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

### Step 3: Memory-Based Scaling
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id "service/my-cluster/my-service" \
  --scalable-dimension "ecs:service:DesiredCount" \
  --policy-name "ecs-memory-scaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageMemoryUtilization"
    },
    "TargetValue": 70.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

### Step 4: Custom Metric Scaling (SQS Queue Depth)
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id "service/my-cluster/my-service" \
  --scalable-dimension "ecs:service:DesiredCount" \
  --policy-name "ecs-sqs-scaling" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-scaling-policy-configuration '{
    "CustomizedMetricSpecification": {
      "MetricName": "ApproximateNumberOfMessagesVisible",
      "Namespace": "AWS/SQS",
      "Dimensions": [{"Name": "QueueName", "Value": "my-processing-queue"}],
      "Statistic": "Average"
    },
    "TargetValue": 100.0
  }'
```

**AWS Services:** ECS Fargate, Application Auto Scaling, ALB, CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 4:

#### Console Step 1: Create an ECR Repository & Push Docker Image
1. Go to **AWS Console** → Search **"ECR"** → Click **Elastic Container Registry**
2. Click **"Create repository"**
3. Repository name: `my-express-app`
4. Click **"Create repository"** ✅
5. Click on the repo → Click **"View push commands"** → Follow the 4 commands to build & push your Docker image

#### Console Step 2: Create an ECS Cluster
1. Go to **AWS Console** → Search **"ECS"** → Click **Elastic Container Service**
2. Click **"Create cluster"**
3. Cluster name: `my-express-cluster`
4. Infrastructure: ✅ **AWS Fargate (serverless)** (should be selected by default)
5. Click **"Create"** ✅

#### Console Step 3: Create a Task Definition
1. In ECS Console → Click **"Task definitions"** → **"Create new task definition"**
2. **Task definition family:** `my-express-task`
3. **Infrastructure requirements:**
   - Launch type: ✅ **AWS Fargate**
   - OS: **Linux/X86_64**
   - CPU: **0.5 vCPU**, Memory: **1 GB**
   - Task role: Select a role with DynamoDB access
   - Task execution role: **ecsTaskExecutionRole**
4. **Container - 1:**
   - Name: `express-app`
   - Image URI: `123456789.dkr.ecr.ap-south-1.amazonaws.com/my-express-app:latest`
   - Port mappings: Container port: `3000`, Protocol: **TCP**
   - **Environment variables:**
     | Key | Value |
     |-----|-------|
     | `DYNAMODB_TABLE_NAME` | `product` |
     | `ORDER_TABLE_NAME` | `order` |
     | `AWS_REGION` | `ap-south-1` |
   - **Health check:** Command: `CMD-SHELL, wget -q --spider http://localhost:3000/health || exit 1`
5. Click **"Create"** ✅

#### Console Step 4: Create a Service with Auto Scaling
1. Go to **ECS** → **Clusters** → Click **my-express-cluster**
2. Click **"Create"** under the Services tab
3. **Environment:**
   - Compute options: ✅ **Launch type** → **FARGATE**
4. **Deployment configuration:**
   - Family: **my-express-task**
   - Service name: `my-express-service`
   - Desired tasks: `2`
5. **Networking:**
   - VPC: Select your VPC
   - Subnets: Select 2+ subnets
   - Security group: Allow port **3000** inbound from ALB security group
   - Public IP: ✅ **Turned on** (for Fargate to pull image from ECR)
6. **Load balancing:**
   - Select ✅ **Application Load Balancer**
   - Create new or use existing ALB
   - Container: `express-app 3000:3000`
   - Target group: Create new → Health check path: `/health`
7. **Service auto scaling:** ← ⭐ THIS IS THE KEY PART
   - ✅ Check **"Use service auto scaling"**
   - Minimum tasks: `2`
   - Maximum tasks: `20`
   - **Scaling policy 1:**
     - Policy name: `cpu-scaling`
     - ECS service metric: **ECSServiceAverageCPUUtilization**
     - Target value: `60`
     - Scale-out cooldown: `60` seconds
     - Scale-in cooldown: `300` seconds
   - Click **"Add another scaling policy"** (optional)
   - **Scaling policy 2:**
     - Policy name: `memory-scaling`
     - ECS service metric: **ECSServiceAverageMemoryUtilization**
     - Target value: `70`
8. Click **"Create"** ✅

#### Console Step 5: Monitor ECS Auto Scaling
1. Go to **ECS** → **Clusters** → **my-express-cluster** → Click **my-express-service**
2. **"Tasks"** tab — Shows running tasks (containers). During scaling, you'll see new tasks appear
3. **"Events"** tab — Shows scaling events:
   ```
   service my-express-service has started 2 tasks: task abc123, task def456
   service my-express-service has reached a steady state
   ```
4. **"Metrics"** tab — Shows CPU/Memory utilization graphs
5. **"Auto Scaling"** tab — Shows current scaling policies and scheduled actions

---

## Use Case 5: Aurora Serverless v2 Auto Scaling (Database)

**Problem:** Database needs vary — light reads during off-hours, heavy writes during batch processing. Fixed DB instances are costly.

**Architecture:**
```
Lambda / ECS → Aurora Serverless v2
                  ├── Min ACU: 0.5 (idle)
                  └── Max ACU: 64 (peak)
                  (1 ACU ≈ 2 GB RAM + proportional CPU)
```

**Steps:**

### Step 1: Create Aurora Serverless v2 Cluster
```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --engine aurora-mysql \
  --engine-version 8.0.mysql_aurora.3.04.0 \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=64 \
  --master-username admin \
  --master-user-password MySecurePassword123!
```

### Step 2: Add a Serverless v2 DB Instance
```bash
aws rds create-db-instance \
  --db-instance-identifier my-serverless-instance \
  --db-cluster-identifier my-serverless-cluster \
  --db-instance-class db.serverless \
  --engine aurora-mysql
```

### Step 3: Monitor Scaling with CloudWatch
```bash
# Watch ACU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time 2026-03-11T00:00:00Z \
  --end-time 2026-03-12T00:00:00Z \
  --period 300 \
  --statistics Average
```

### Step 4: Set Alarms
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "aurora-high-acu" \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --statistic Average \
  --period 300 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions arn:aws:sns:ap-south-1:123456789:my-alerts
```

**AWS Services:** Aurora Serverless v2, CloudWatch, SNS

---

### 🖥️ AWS Console (Panel) Steps for Use Case 5:

#### Console Step 1: Create Aurora Serverless v2 Cluster
1. Go to **AWS Console** → Search **"RDS"** → Click **RDS**
2. Click **"Create database"**
3. **Choose a database creation method:**
   - ✅ **Standard create**
4. **Engine options:**
   - Engine type: **Aurora (MySQL Compatible)** or **Aurora (PostgreSQL Compatible)**
   - Edition: **Aurora (MySQL Compatible)**
   - Engine version: **Aurora MySQL 3.04.0** (compatible with MySQL 8.0)
5. **Templates:**
   - ✅ **Production** (or Dev/Test for testing)
6. **Settings:**
   - DB cluster identifier: `my-serverless-cluster`
   - Master username: `admin`
   - Master password: Choose a secure password
7. **Instance configuration:** ← ⭐ KEY SECTION
   - DB instance class: ✅ **Serverless v2**
   - **Capacity range:**
     | Setting | Value |
     |---------|-------|
     | Minimum ACUs | `0.5` (minimum possible — costs ~$0.06/hour idle) |
     | Maximum ACUs | `64` (maximum — scales up to handle heavy load) |
   > 1 ACU ≈ 2 GB RAM + proportional CPU
8. **Connectivity:**
   - VPC: Select your VPC
   - Public access: **No** (access only from Lambda/ECS within VPC)
   - Security group: Allow port **3306** (MySQL) from Lambda/ECS security group
9. Click **"Create database"** ✅
10. Wait 5-10 minutes for cluster to become **"Available"**

#### Console Step 2: Monitor Serverless v2 Scaling
1. Go to **RDS Console** → Click **my-serverless-cluster**
2. Click the **"Monitoring"** tab
3. Key metrics to watch:
   - **ServerlessDatabaseCapacity** — Current ACUs being used (shows scaling in real-time)
   - **ACUUtilization** — How much of max capacity is being used
   - **DatabaseConnections** — Number of active connections
4. During idle: ACUs will drop to **0.5** (minimum)
5. During heavy load: ACUs will ramp up to **64** (maximum)

#### Console Step 3: Set CloudWatch Alarms
1. Go to **CloudWatch Console** → **"Alarms"** → **"Create alarm"**
2. Click **"Select metric"** → **RDS** → **Per-Database Metrics**
3. Search for `my-serverless-cluster` → Select **ServerlessDatabaseCapacity**
4. **Conditions:**
   - Threshold type: **Static**
   - Whenever ServerlessDatabaseCapacity is **Greater than** `50`
   - For `3` consecutive periods of `5 minutes`
5. **Notification:**
   - Send to SNS topic: Select or create topic
   - Email: `your-email@example.com`
6. Alarm name: `aurora-high-acu`
7. Click **"Create alarm"** ✅

> This alerts you when the database is using high capacity, so you can investigate or increase max ACUs.

---

## Use Case 6: SQS-Based Auto Scaling (Worker Pattern)

**Problem:** Background workers (EC2 or ECS) need to scale based on queue depth — more messages = more workers.

**Architecture:**
```
Express API (producer) → SQS Queue → Auto Scaled Workers (Node.js consumers)
                                        ├── Worker 1 → Process & Save to DynamoDB
                                        ├── Worker 2 → Process & Save to DynamoDB
                                        └── Worker N    ← Scale on queue depth
```

### Your Node.js Code — Producer (Express API) + Consumer (Worker)

**producer-api.js** — Express app that sends messages to SQS (similar to your basket checkout):
```javascript
import express from 'express';
import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';

const app = express();
const sqsClient = new SQSClient({ region: 'ap-south-1' });
const QUEUE_URL = process.env.SQS_QUEUE_URL;

app.use(express.json());

// POST /checkout — sends order to SQS (like your basket microservice)
app.post('/checkout', async (req, res) => {
  try {
    const orderData = {
      userName: req.body.userName,
      totalPrice: req.body.totalPrice,
      items: req.body.items,
      checkoutDate: new Date().toISOString()
    };

    // Send to SQS — workers will pick this up
    await sqsClient.send(new SendMessageCommand({
      QueueUrl: QUEUE_URL,
      MessageBody: JSON.stringify(orderData),
      MessageAttributes: {
        orderType: { DataType: 'String', StringValue: 'checkout' }
      }
    }));

    console.log(`Order queued for ${orderData.userName}`);
    res.status(202).json({ message: 'Order queued for processing', order: orderData });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Bulk send — to test auto scaling (flood the queue)
app.post('/stress-queue', async (req, res) => {
  const count = parseInt(req.query.count) || 100;
  const promises = [];

  for (let i = 0; i < count; i++) {
    promises.push(sqsClient.send(new SendMessageCommand({
      QueueUrl: QUEUE_URL,
      MessageBody: JSON.stringify({
        userName: `stress-user-${i}`,
        totalPrice: Math.random() * 500,
        items: [{ name: `item-${i}`, qty: 1 }],
        checkoutDate: new Date().toISOString()
      })
    })));
  }

  await Promise.all(promises);
  res.json({ message: `${count} messages sent to queue — watch workers scale up!` });
});

app.listen(3000, () => console.log('Producer API on port 3000'));
```

**worker.js** — SQS consumer (runs on each auto-scaled EC2/ECS instance):
```javascript
import { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } from '@aws-sdk/client-sqs';
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';
import os from 'os';

const sqsClient = new SQSClient({ region: 'ap-south-1' });
const ddbClient = new DynamoDBClient({ region: 'ap-south-1' });
const QUEUE_URL = process.env.SQS_QUEUE_URL;
const TABLE_NAME = process.env.ORDER_TABLE_NAME || 'order';

const processMessage = async (message) => {
  const orderData = JSON.parse(message.Body);
  console.log(`[Worker: ${os.hostname()}] Processing order for ${orderData.userName}`);

  // Save to DynamoDB — same as your createOrder() function
  orderData.orderDate = new Date().toISOString();
  orderData.processedBy = os.hostname(); // Track which worker processed it

  await ddbClient.send(new PutItemCommand({
    TableName: TABLE_NAME,
    Item: marshall(orderData)
  }));

  console.log(`[Worker: ${os.hostname()}] Order saved for ${orderData.userName}`);
};

// Long-polling loop — each worker instance runs this continuously
const pollQueue = async () => {
  console.log(`🔄 Worker ${os.hostname()} started polling SQS...`);

  while (true) {
    try {
      const { Messages } = await sqsClient.send(new ReceiveMessageCommand({
        QueueUrl: QUEUE_URL,
        MaxNumberOfMessages: 10,   // Process up to 10 messages per batch
        WaitTimeSeconds: 20,       // Long polling — wait up to 20s for messages
        VisibilityTimeout: 60      // Hide message from other workers for 60s
      }));

      if (Messages && Messages.length > 0) {
        console.log(`[Worker: ${os.hostname()}] Received ${Messages.length} messages`);

        for (const message of Messages) {
          await processMessage(message);

          // Delete message after successful processing
          await sqsClient.send(new DeleteMessageCommand({
            QueueUrl: QUEUE_URL,
            ReceiptHandle: message.ReceiptHandle
          }));
        }
      }
    } catch (e) {
      console.error(`[Worker: ${os.hostname()}] Error:`, e.message);
      await new Promise(r => setTimeout(r, 5000)); // Wait 5s before retrying
    }
  }
};

pollQueue();
```

> 💡 **How to prove SQS auto scaling works:**
> 1. Call `POST /stress-queue?count=500` to flood the queue with 500 messages
> 2. Watch CloudWatch metric `ApproximateNumberOfMessagesVisible` spike
> 3. Auto Scaling launches new worker instances
> 4. Check DynamoDB — the `processedBy` field shows **different worker hostnames**
> 5. Once queue drains, workers scale back down

**Steps:**

### Step 1: Create Custom CloudWatch Metric (Backlog Per Instance)
```bash
# This metric = ApproximateNumberOfMessages / NumberOfRunningInstances
# Target: each worker should process ~10 messages at a time
```

### Step 2: Step Scaling Policy
```bash
# Scale OUT when queue > 100 messages
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-worker-asg \
  --policy-name "sqs-scale-out" \
  --policy-type "StepScaling" \
  --adjustment-type "ChangeInCapacity" \
  --step-adjustments '[
    {"MetricIntervalLowerBound": 0, "MetricIntervalUpperBound": 500, "ScalingAdjustment": 2},
    {"MetricIntervalLowerBound": 500, "MetricIntervalUpperBound": 2000, "ScalingAdjustment": 5},
    {"MetricIntervalLowerBound": 2000, "ScalingAdjustment": 10}
  ]'

# Scale IN when queue < 10 messages
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-worker-asg \
  --policy-name "sqs-scale-in" \
  --policy-type "StepScaling" \
  --adjustment-type "ChangeInCapacity" \
  --step-adjustments '[
    {"MetricIntervalUpperBound": 0, "ScalingAdjustment": -2}
  ]'
```

### Step 3: Create CloudWatch Alarm for Queue Depth
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "sqs-high-depth" \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=my-processing-queue \
  --statistic Average \
  --period 60 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:autoscaling:ap-south-1:123456789:scalingPolicy:abc123

aws cloudwatch put-metric-alarm \
  --alarm-name "sqs-low-depth" \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=my-processing-queue \
  --statistic Average \
  --period 300 \
  --threshold 10 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions arn:aws:autoscaling:ap-south-1:123456789:scalingPolicy:def456
```

**AWS Services:** SQS, EC2 Auto Scaling / ECS, CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 6:

#### Console Step 1: Create an SQS Queue
1. Go to **AWS Console** → Search **"SQS"** → Click **Simple Queue Service**
2. Click **"Create queue"**
3. **Details:**
   - Type: ✅ **Standard** (high throughput, best-effort ordering)
   - Name: `my-processing-queue`
4. **Configuration:**
   - Visibility timeout: `60` seconds (time to process one message)
   - Message retention period: `4` days
   - Receive message wait time: `20` seconds (long polling — saves cost)
5. **Dead-letter queue:**
   - ✅ **Enabled**
   - Choose queue: Click **"Create new DLQ"** → Name: `my-processing-queue-dlq` → **Create**
   - Maximum receives: `3` (after 3 failures, message goes to DLQ)
6. Click **"Create queue"** ✅
7. Note the **Queue URL** (you'll need this for your worker code)

#### Console Step 2: Create Auto Scaling Group for Workers
1. Follow **Use Case 1 Console Steps 1-3** to create:
   - Launch Template: `my-worker-template` (UserData runs `worker.js` instead of `app.js`)
   - Auto Scaling Group: `my-worker-asg`
     - Minimum: `1`, Maximum: `20`, Desired: `1`
     - **Don't attach a load balancer** (workers don't serve HTTP)

#### Console Step 3: Create CloudWatch Alarm for Queue Depth
1. Go to **CloudWatch Console** → **"Alarms"** → **"Create alarm"**
2. Click **"Select metric"** → **SQS** → **Queue Metrics**
3. Select **my-processing-queue** → Metric: **ApproximateNumberOfMessagesVisible**
4. **Conditions (Scale OUT alarm):**
   - Threshold: **Greater than** `100`
   - For `2` consecutive periods of `1 minute`
5. **Notification & Auto Scaling Action:**
   - ✅ **EC2 Auto Scaling action**
   - Select **my-worker-asg**
   - Action: **Add `2` capacity units**
6. Alarm name: `sqs-high-depth`
7. Click **"Create alarm"** ✅

#### Console Step 4: Create Scale-IN Alarm
1. **"Create alarm"** again → Same metric → **ApproximateNumberOfMessagesVisible**
2. **Conditions:**
   - Threshold: **Less than** `10`
   - For `3` consecutive periods of `5 minutes`
3. **Action:**
   - ✅ **EC2 Auto Scaling action**
   - Select **my-worker-asg**
   - Action: **Remove `2` capacity units**
4. Alarm name: `sqs-low-depth`
5. Click **"Create alarm"** ✅

#### Console Step 5: Verify
1. Go to **SQS Console** → Click **my-processing-queue**
2. Click **"Send and receive messages"** → Send a few test messages
3. Go to **EC2** → **Auto Scaling Groups** → **my-worker-asg** → **"Activity"** tab
4. When queue depth exceeds 100, you should see: `Launching a new EC2 instance`
5. When queue drains below 10, you should see: `Terminating an EC2 instance`

---

## Use Case 7: Predictive Auto Scaling (Machine Learning Based)

**Problem:** Reactive scaling is too slow for sudden traffic spikes (e.g., flash sales, game launches). You need to scale BEFORE traffic arrives.

**Architecture:**
```
CloudWatch Metrics (historical) → Predictive Scaling → Pre-scale EC2 ASG
                                                         ├── Instance 1
                                                         ├── Instance 2
                                                         └── Instance N (pre-warmed)
```

**Steps:**

### Step 1: Enable Predictive Scaling
```bash
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-web-app-asg \
  --policy-name "predictive-scaling" \
  --policy-type "PredictiveScaling" \
  --predictive-scaling-configuration '{
    "MetricSpecifications": [{
      "TargetValue": 60.0,
      "PredefinedMetricPairSpecification": {
        "PredefinedMetricType": "ASGCPUUtilization"
      }
    }],
    "Mode": "ForecastAndScale",
    "SchedulingBufferTime": 300,
    "MaxCapacityBreachBehavior": "IncreaseMaxCapacity",
    "MaxCapacityBuffer": 20
  }'
```

### Step 2: Combine with Target Tracking (Best Practice)
```bash
# Predictive scaling handles expected patterns
# Target tracking handles unexpected spikes
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name my-web-app-asg \
  --policy-name "reactive-cpu-tracking" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 60.0
  }'
```

### Step 3: View Predictions
```bash
aws autoscaling get-predictive-scaling-forecast \
  --auto-scaling-group-name my-web-app-asg \
  --policy-name "predictive-scaling" \
  --start-time 2026-03-12T00:00:00Z \
  --end-time 2026-03-13T00:00:00Z
```

> ⚠️ **Note:** Predictive scaling needs **14 days of historical data** to generate accurate forecasts.

**AWS Services:** EC2 Auto Scaling (Predictive), CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 7:

#### Console Step 1: Enable Predictive Scaling
1. Go to **EC2 Console** → **"Auto Scaling Groups"** → Click **my-web-app-asg**
2. Click **"Automatic scaling"** tab
3. Click **"Create predictive scaling policy"**
4. **Policy settings:**
   - Policy name: `predictive-scaling`
   - **Scaling metric:** ✅ **CPU utilization** (or custom metric pair)
   - Target utilization: `60` (%)
   - **Predictive scaling mode:**
     - ✅ **Forecast and scale** (actively scales based on ML prediction)
     - _(Other option: "Forecast only" — just shows predictions, doesn't scale)_
   - **Pre-launch time:** `5 minutes` (launch instances 5 min before predicted spike)
   - **Max capacity behavior:**
     - ✅ **Increase max capacity above forecast** by `20`%
5. Click **"Create"** ✅

#### Console Step 2: View Forecast (after 14 days of data)
1. Go to **EC2** → **Auto Scaling Groups** → **my-web-app-asg**
2. Click **"Automatic scaling"** tab
3. Under **Predictive scaling policies** → Click on **predictive-scaling**
4. You'll see a graph showing:
   ```
   ┌──────────────────────────────────────────────┐
   │ ▓▓▓▓       Predicted Capacity                │
   │ ░░░░       Actual Capacity                    │
   │                                               │
   │    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓                            │
   │   ▓              ▓▓▓                          │
   │  ▓                  ▓▓▓                       │
   │ ▓░░░░░░░░░░░░░░░░░░░░▓                       │
   │▓░                     ░▓▓▓                    │
   │░                          ░░░░░░             │
   │                                               │
   │ 12AM   6AM   12PM   6PM   12AM               │
   └──────────────────────────────────────────────┘
   ```
5. The graph shows predicted vs actual traffic patterns

> ⚠️ **Important:** Predictive scaling needs **at least 14 days of historical data** to generate accurate forecasts. The graph will be empty until then.

#### Console Step 3: Combine with Target Tracking (Best Practice)
1. On the same **"Automatic scaling"** tab
2. You should have **BOTH** policies active:
   - ✅ **Predictive scaling** — handles expected daily/weekly patterns
   - ✅ **Target tracking** — handles unexpected spikes (from Use Case 1 setup)
3. Both work together — predictive scales proactively, target tracking reacts to surprises

---

## Use Case 8: Scheduled Auto Scaling (Time-Based)

**Problem:** Traffic patterns are predictable — high during business hours, low at night/weekends. Scale proactively based on schedule.

**Architecture:**
```
Schedule: 8 AM → Scale to 10 instances
Schedule: 6 PM → Scale to 3 instances
Schedule: Weekend → Scale to 2 instances
```

**Steps:**

### Step 1: Scale Up for Business Hours (Weekdays 8 AM)
```bash
aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-web-app-asg \
  --scheduled-action-name "weekday-morning-scale-up" \
  --recurrence "0 8 * * MON-FRI" \
  --min-size 5 \
  --max-size 20 \
  --desired-capacity 10
```

### Step 2: Scale Down for Evening (Weekdays 6 PM)
```bash
aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-web-app-asg \
  --scheduled-action-name "weekday-evening-scale-down" \
  --recurrence "0 18 * * MON-FRI" \
  --min-size 2 \
  --max-size 10 \
  --desired-capacity 3
```

### Step 3: Weekend Minimum
```bash
aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-web-app-asg \
  --scheduled-action-name "weekend-scale-down" \
  --recurrence "0 0 * * SAT" \
  --min-size 2 \
  --max-size 5 \
  --desired-capacity 2
```

### Step 4: Special Events (One-Time)
```bash
# Black Friday scale-up
aws autoscaling put-scheduled-update-group-action \
  --auto-scaling-group-name my-web-app-asg \
  --scheduled-action-name "black-friday-2026" \
  --start-time "2026-11-27T06:00:00Z" \
  --min-size 20 \
  --max-size 50 \
  --desired-capacity 30
```

**AWS Services:** EC2 Auto Scaling (Scheduled), CloudWatch

---

### 🖥️ AWS Console (Panel) Steps for Use Case 8:

#### Console Step 1: Create Scheduled Scaling Actions
1. Go to **EC2 Console** → **"Auto Scaling Groups"** → Click **my-web-app-asg**
2. Click **"Automatic scaling"** tab
3. Scroll to **"Scheduled actions"** section
4. Click **"Create scheduled action"**

#### Console Step 2: Morning Scale-Up (Weekdays 8 AM)
5. **Scheduled action settings:**
   - Name: `weekday-morning-scale-up`
   - Desired capacity: `10`
   - Min: `5`
   - Max: `20`
   - Recurrence: ✅ **Cron** → `0 8 * * MON-FRI`
   - Time zone: Select your timezone (e.g., **Asia/Kolkata**)
6. Click **"Create"** ✅

#### Console Step 3: Evening Scale-Down (Weekdays 6 PM)
7. Click **"Create scheduled action"** again
8. **Settings:**
   - Name: `weekday-evening-scale-down`
   - Desired capacity: `3`
   - Min: `2`
   - Max: `10`
   - Recurrence: ✅ **Cron** → `0 18 * * MON-FRI`
9. Click **"Create"** ✅

#### Console Step 4: Weekend Minimum
10. Click **"Create scheduled action"** again
11. **Settings:**
    - Name: `weekend-scale-down`
    - Desired capacity: `2`
    - Min: `2`
    - Max: `5`
    - Recurrence: ✅ **Cron** → `0 0 * * SAT`
12. Click **"Create"** ✅

#### Console Step 5: Special Event (One-Time)
13. Click **"Create scheduled action"** again
14. **Settings:**
    - Name: `black-friday-2026`
    - Desired capacity: `30`
    - Min: `20`
    - Max: `50`
    - Recurrence: ✅ **Once** (not recurring)
    - Start time: `2026-11-27 06:00 UTC`
    - End time: `2026-11-28 06:00 UTC`
15. Click **"Create"** ✅

#### Console Step 6: View All Scheduled Actions
1. On the **"Automatic scaling"** tab → **"Scheduled actions"** section
2. You should see all 4 actions listed:
   ```
   ┌─────────────────────────────┬──────┬─────┬──────┬────────────────────┐
   │ Name                        │ Des. │ Min │ Max  │ Recurrence         │
   ├─────────────────────────────┼──────┼─────┼──────┼────────────────────┤
   │ weekday-morning-scale-up    │ 10   │ 5   │ 20   │ 0 8 * * MON-FRI   │
   │ weekday-evening-scale-down  │ 3    │ 2   │ 10   │ 0 18 * * MON-FRI  │
   │ weekend-scale-down          │ 2    │ 2   │ 5    │ 0 0 * * SAT       │
   │ black-friday-2026           │ 30   │ 20  │ 50   │ Once (Nov 27)     │
   └─────────────────────────────┴──────┴─────┴──────┴────────────────────┘
   ```
3. Check the **"Activity"** tab to confirm scaling happens at the scheduled times

---

## Quick Comparison Table

| # | Use Case | Scaling Target | Scaling Trigger | Best For |
|---|---|---|---|---|
| 1 | EC2 ASG | EC2 Instances | CPU / Request Count | Web apps, APIs |
| 2 | DynamoDB | Read/Write Capacity | Utilization % | Database throughput |
| 3 | Lambda Concurrency | Provisioned Concurrency | Utilization % | Low-latency APIs |
| 4 | ECS Fargate | Container Tasks | CPU / Memory / Custom | Microservices |
| 5 | Aurora Serverless | ACUs (compute units) | Automatic | Variable DB workloads |
| 6 | SQS Workers | EC2/ECS Workers | Queue Depth | Background processing |
| 7 | Predictive Scaling | EC2 Instances | ML Forecast | Predictable patterns |
| 8 | Scheduled Scaling | EC2/ECS/Lambda | Time-based cron | Business hours traffic |

---

## Scaling Policy Types Summary

| Policy Type | How It Works | Best For |
|---|---|---|
| **Target Tracking** | Maintains a metric at a target value (like a thermostat) | Most use cases (recommended default) |
| **Step Scaling** | Adds/removes capacity in steps based on alarm thresholds | Fine-grained control over scaling speed |
| **Simple Scaling** | One alarm → one adjustment, then waits for cooldown | Basic use cases (legacy) |
| **Scheduled** | Scale at specific times using cron expressions | Predictable traffic patterns |
| **Predictive** | ML analyzes past traffic to pre-scale before demand | Recurring daily/weekly patterns |

---

## Best Practices

1. **Combine policies** — Use Predictive + Target Tracking together for best results
2. **Scale out fast, scale in slow** — Set shorter `ScaleOutCooldown` (60s) and longer `ScaleInCooldown` (300s)
3. **Use multiple AZs** — Distribute across 3+ Availability Zones for high availability
4. **Health checks** — Enable ELB health checks (not just EC2 status checks)
5. **Warm-up time** — Set `EstimatedInstanceWarmup` to account for boot/initialization time
6. **Instance protection** — Protect instances running long jobs from scale-in termination
7. **Monitor with CloudWatch Dashboards** — Track scaling events, instance count, and costs
8. **Use mixed instance types** — Combine On-Demand + Spot instances for cost savings

---

---

## 🧪 How to Verify Auto Scaling is Working (with Your Express App)

### Test 1: Check Which Instance Handles Your Request
```bash
# Hit the endpoint multiple times — watch the instance/container change
for i in {1..20}; do
  curl -s http://YOUR-ALB-URL/health | jq '.hostname'
  sleep 1
done

# Output shows different instances handling requests:
# "ip-10-0-1-45"    ← Instance in AZ-1a
# "ip-10-0-2-78"    ← Instance in AZ-1b
# "ip-10-0-1-45"    ← Back to AZ-1a (round robin)
# "ip-10-0-3-12"    ← NEW instance launched by auto scaling!
```

### Test 2: Trigger Scale-Out with Load
```bash
# Install load testing tool
npm install -g autocannon

# Hit the Express app with 200 concurrent connections for 60 seconds
autocannon -c 200 -d 60 http://YOUR-ALB-URL/products

# OR use the built-in stress endpoint
for i in {1..50}; do
  curl -s http://YOUR-ALB-URL/stress-test &
done
wait

# Watch instances scale out:
watch -n 5 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names my-web-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Running:Instances[?LifecycleState==\`InService\`]|length(@)}'"
```

### Test 3: Verify in Your Express Response
```bash
# Before load — 2 unique instances
curl http://YOUR-ALB-URL/health
# {"status":"healthy","hostname":"ip-10-0-1-45","uptime":3600}

# During load — auto scaling adds instances, you see NEW hostnames
curl http://YOUR-ALB-URL/health
# {"status":"healthy","hostname":"ip-10-0-3-99","uptime":30}  ← New! uptime=30s

# After load — instances scale back down (after cooldown period)
```

### Test 4: Check Scaling Activity Logs
```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name my-web-app-asg \
  --max-items 5 \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Cause:Cause}'
```

---

## 👉 Next Step

**Tell me which use case number(s) you want to implement or explore further, and I'll build it out in detail!**
