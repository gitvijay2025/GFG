# Practical AWS Lambda Use Cases & Step-by-Step Solutions

> **Instructions:** Review the use cases below and tell me which one(s) you'd like to implement. ✅ marks use cases already implemented in this project.

---

## Use Case 1: ✅ Serverless REST API (Already Implemented)

**Problem:** Build CRUD microservices without managing servers.

**Architecture:**
```
Client → API Gateway (REST) → Lambda → DynamoDB
```

**Steps:**
1. Create a DynamoDB table with partition key (e.g., `id`)
2. Write a Lambda handler that switches on `event.httpMethod` (GET, POST, PUT, DELETE)
3. Use `@aws-sdk/client-dynamodb` with `marshall/unmarshall` for data operations
4. Create an API Gateway REST API with `{proxy+}` resource
5. Connect routes to the Lambda function with Lambda Proxy Integration
6. Deploy and test endpoints with `curl` or Postman

**AWS Services:** API Gateway, Lambda, DynamoDB

**Your Implementation:** `src/product/index.js`, `src/basket/index.js`, `src/ordering/index.js`

---

## Use Case 2: ✅ Event-Driven Order Processing (Already Implemented)

**Problem:** Decouple checkout from order creation using async messaging.

**Architecture:**
```
Lambda (Basket) → EventBridge → SQS Queue → Lambda (Ordering) → DynamoDB
```

**Steps:**
1. Basket Lambda publishes a `CheckoutBasket` event to EventBridge using `PutEventsCommand`
2. Create an EventBridge rule matching `detail-type: "CheckoutBasket"`
3. Set the rule target to an SQS queue (provides buffering and retry)
4. Ordering Lambda polls SQS, parses the event body, and writes order to DynamoDB
5. Configure a Dead Letter Queue (DLQ) for messages that fail after max retries
6. Add CloudWatch alarms on DLQ message count

**AWS Services:** Lambda, EventBridge, SQS, DynamoDB, CloudWatch

**Your Implementation:** `src/basket/index.js` (publisher), `src/ordering/index.js` (consumer)

---

## Use Case 3: Image/File Processing Pipeline

**Problem:** Automatically resize images or process files when uploaded to S3.

**Architecture:**
```
User Upload → S3 (my-app-uploads) → Lambda (process) → S3 (my-app-processed)
                                                      → DynamoDB (image-metadata)
```

**AWS Services:** S3, Lambda, DynamoDB, SNS, IAM

---

### Step 1: Create Two S3 Buckets

**Option A — AWS CLI:**
```bash
# Create the upload bucket (where users upload raw files)
aws s3api create-bucket \
  --bucket my-app-uploads \
  --region us-east-1

# Create the processed bucket (where Lambda saves processed files)
aws s3api create-bucket \
  --bucket my-app-processed \
  --region us-east-1

# Verify both buckets exist
aws s3 ls | grep my-app
```

> ⚠️ **For regions other than us-east-1**, add `--create-bucket-configuration LocationConstraint=<region>`:
> ```bash
> aws s3api create-bucket \
>   --bucket my-app-uploads \
>   --region ap-south-1 \
>   --create-bucket-configuration LocationConstraint=ap-south-1
> ```

**Option B — AWS Console (Step-by-Step with Screenshots Guide):**

**Create Bucket 1: `my-app-uploads`**
1. Login to **AWS Management Console** → Search **"S3"** in the top search bar → Click **S3**
2. Click the orange **"Create bucket"** button (top right)
3. **General configuration:**
   - Bucket name: `my-app-uploads`
   - AWS Region: **US East (N. Virginia) us-east-1** (or your preferred region)
4. **Object Ownership:**
   - Select ✅ **ACLs disabled (recommended)**
5. **Block Public Access settings for this bucket:**
   - ✅ Keep **"Block all public access"** checked (default — leave it ON)
6. **Bucket Versioning:**
   - Select ✅ **Enable** (recommended — allows recovery of overwritten/deleted files)
7. **Default encryption:**
   - Encryption type: **Server-side encryption with Amazon S3 managed keys (SSE-S3)**
   - Bucket Key: **Enable** (reduces KMS costs)
8. Click **"Create bucket"** ✅

**Create Bucket 2: `my-app-processed`**
9. Back on S3 dashboard → Click **"Create bucket"** again
10. Bucket name: `my-app-processed`
11. Keep all other settings same as above
12. Click **"Create bucket"** ✅

**Verify:**
13. You should now see both buckets in the S3 dashboard:
    ```
    📁 my-app-uploads
    📁 my-app-processed
    ```

**Option C — Terraform (add to your `terraform/` folder):**
```hcl
# terraform/s3.tf

resource "aws_s3_bucket" "uploads" {
  bucket = "my-app-uploads"

  tags = {
    Name        = "Upload Bucket"
    Environment = "production"
    Project     = "aws-microservices"
  }
}

resource "aws_s3_bucket" "processed" {
  bucket = "my-app-processed"

  tags = {
    Name        = "Processed Bucket"
    Environment = "production"
    Project     = "aws-microservices"
  }
}

# Block public access on both buckets (security best practice)
resource "aws_s3_bucket_public_access_block" "uploads_block" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_block" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Option D — CDK (TypeScript, matches your project):**
```typescript
// In lib/aws-microservices-stack.ts
import * as s3 from 'aws-cdk-lib/aws-s3';

const uploadBucket = new s3.Bucket(this, 'UploadBucket', {
  bucketName: 'my-app-uploads',
  removalPolicy: cdk.RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
});

const processedBucket = new s3.Bucket(this, 'ProcessedBucket', {
  bucketName: 'my-app-processed',
  removalPolicy: cdk.RemovalPolicy.DESTROY,
  autoDeleteObjects: true,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
});
```

---

### Step 2: Create the DynamoDB Metadata Table

**Option A — AWS CLI:**
```bash
aws dynamodb create-table \
  --table-name image-metadata \
  --attribute-definitions \
    AttributeName=imageId,AttributeType=S \
  --key-schema \
    AttributeName=imageId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**Option B — AWS Console (Step-by-Step):**
1. Go to **AWS Console** → Search **"DynamoDB"** → Click **DynamoDB**
2. In the left sidebar, click **"Tables"**
3. Click the orange **"Create table"** button
4. **Table details:**
   - Table name: `image-metadata`
   - Partition key: `imageId` → Type: **String**
   - Sort key: _(leave empty)_
5. **Table settings:**
   - Select ✅ **Customize settings**
6. **Read/write capacity settings:**
   - Capacity mode: Select ✅ **On-demand** (auto-scales, no capacity planning needed)
7. **Encryption at rest:**
   - Select ✅ **Owned by Amazon DynamoDB** (free, default)
8. Click **"Create table"** ✅
9. Wait until Status changes to **"Active"** (takes ~10-15 seconds)

---

### Step 3: Create the IAM Role for Lambda

**Option A — AWS CLI:**
```bash
# Create the execution role
aws iam create-role \
  --role-name image-processor-lambda-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach policies
aws iam attach-role-policy \
  --role-name image-processor-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create inline policy for S3 + DynamoDB access
aws iam put-role-policy \
  --role-name image-processor-lambda-role \
  --policy-name s3-dynamodb-access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject"],
        "Resource": "arn:aws:s3:::my-app-uploads/*"
      },
      {
        "Effect": "Allow",
        "Action": ["s3:PutObject"],
        "Resource": "arn:aws:s3:::my-app-processed/*"
      },
      {
        "Effect": "Allow",
        "Action": ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"],
        "Resource": "arn:aws:dynamodb:us-east-1:*:table/image-metadata"
      }
    ]
  }'
```

**Option B — AWS Console (Step-by-Step):**
1. Go to **AWS Console** → Search **"IAM"** → Click **IAM**
2. In the left sidebar, click **"Roles"**
3. Click **"Create role"** button
4. **Trusted entity type:**
   - Select ✅ **AWS service**
5. **Use case:**
   - Service: **Lambda**
   - Click **"Next"**
6. **Add permissions — Attach policies:**
   - Search and check ✅ **AWSLambdaBasicExecutionRole** (for CloudWatch Logs)
   - Click **"Next"**
7. **Name, review, and create:**
   - Role name: `image-processor-lambda-role`
   - Description: `Allows Lambda to read/write S3 and DynamoDB for image processing`
   - Click **"Create role"** ✅
8. **Add custom inline policy (for S3 + DynamoDB access):**
   - Click on the newly created role **"image-processor-lambda-role"**
   - Go to **"Permissions"** tab → Click **"Add permissions"** → **"Create inline policy"**
   - Click the **"JSON"** tab and paste:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:GetObject"],
         "Resource": "arn:aws:s3:::my-app-uploads/*"
       },
       {
         "Effect": "Allow",
         "Action": ["s3:PutObject"],
         "Resource": "arn:aws:s3:::my-app-processed/*"
       },
       {
         "Effect": "Allow",
         "Action": ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"],
         "Resource": "arn:aws:dynamodb:us-east-1:*:table/image-metadata"
       }
     ]
   }
   ```
   - Click **"Next"**
   - Policy name: `s3-dynamodb-access`
   - Click **"Create policy"** ✅

---

### Step 4: Write the Lambda Function Code

**src/image-processor/index.js:**
```javascript
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { marshall } from "@aws-sdk/util-dynamodb";
import sharp from "sharp";

const s3Client = new S3Client({ region: process.env.AWS_REGION || "us-east-1" });
const ddbClient = new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" });

export const handler = async (event) => {
  console.log("S3 Event received:", JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    const sourceBucket = record.s3.bucket.name;
    const sourceKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    const fileSize = record.s3.object.size;

    console.log(`Processing: ${sourceBucket}/${sourceKey} (${fileSize} bytes)`);

    try {
      // 1. Download the original image from uploads bucket
      const getResponse = await s3Client.send(new GetObjectCommand({
        Bucket: sourceBucket,
        Key: sourceKey
      }));

      const imageBuffer = Buffer.from(await getResponse.Body.transformToByteArray());
      console.log(`Downloaded: ${sourceKey} (${imageBuffer.length} bytes)`);

      // 2. Get original image metadata
      const metadata = await sharp(imageBuffer).metadata();
      console.log(`Original: ${metadata.width}x${metadata.height}, format: ${metadata.format}`);

      // 3. Create multiple resized versions
      const sizes = [
        { name: "thumbnail", width: 150, height: 150 },
        { name: "medium", width: 600, height: 600 },
        { name: "large", width: 1200, height: 1200 }
      ];

      const processedFiles = [];

      for (const size of sizes) {
        const resized = await sharp(imageBuffer)
          .resize(size.width, size.height, { fit: "inside", withoutEnlargement: true })
          .jpeg({ quality: 80 })
          .toBuffer();

        const processedKey = `${size.name}/${sourceKey.replace(/\.[^.]+$/, ".jpg")}`;

        // 4. Upload resized image to processed bucket
        await s3Client.send(new PutObjectCommand({
          Bucket: process.env.PROCESSED_BUCKET,
          Key: processedKey,
          Body: resized,
          ContentType: "image/jpeg",
          Metadata: {
            "original-key": sourceKey,
            "resize-dimensions": `${size.width}x${size.height}`
          }
        }));

        console.log(`Uploaded: ${processedKey} (${resized.length} bytes)`);
        processedFiles.push({
          size: size.name,
          key: processedKey,
          bytes: resized.length
        });
      }

      // 5. Save metadata to DynamoDB
      const imageId = sourceKey.replace(/[^a-zA-Z0-9-_]/g, "_");
      await ddbClient.send(new PutItemCommand({
        TableName: process.env.METADATA_TABLE,
        Item: marshall({
          imageId: imageId,
          originalKey: sourceKey,
          originalBucket: sourceBucket,
          originalSize: fileSize,
          originalWidth: metadata.width,
          originalHeight: metadata.height,
          originalFormat: metadata.format,
          processedFiles: processedFiles,
          processedAt: new Date().toISOString(),
          status: "completed"
        })
      }));

      console.log(`✅ Successfully processed: ${sourceKey}`);

    } catch (error) {
      console.error(`❌ Failed to process ${sourceKey}:`, error);

      // Save failure metadata
      await ddbClient.send(new PutItemCommand({
        TableName: process.env.METADATA_TABLE,
        Item: marshall({
          imageId: sourceKey.replace(/[^a-zA-Z0-9-_]/g, "_"),
          originalKey: sourceKey,
          status: "failed",
          error: error.message,
          failedAt: new Date().toISOString()
        })
      }));

      throw error; // Re-throw so Lambda marks this as failed
    }
  }

  return { statusCode: 200, body: "Processing complete" };
};
```

**src/image-processor/package.json:**
```json
{
  "name": "image-processor",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@aws-sdk/client-s3": "^3.400.0",
    "@aws-sdk/client-dynamodb": "^3.400.0",
    "@aws-sdk/util-dynamodb": "^3.400.0",
    "sharp": "^0.33.0"
  }
}
```

---

### Step 5: Package and Deploy the Lambda Function

**Option A — AWS CLI:**
```bash
# Install dependencies (sharp needs native binaries for Lambda's Amazon Linux)
cd src/image-processor
npm install
npm install --os=linux --cpu=x64 sharp  # Cross-compile for Lambda

# Zip the function
zip -r ../../image-processor.zip .

# Create the Lambda function
cd ../..
aws lambda create-function \
  --function-name imageProcessor \
  --runtime nodejs20.x \
  --handler index.handler \
  --role arn:aws:iam::123456789012:role/image-processor-lambda-role \
  --zip-file fileb://image-processor.zip \
  --timeout 60 \
  --memory-size 1024 \
  --environment Variables='{
    "PROCESSED_BUCKET": "my-app-processed",
    "METADATA_TABLE": "image-metadata"
  }'
```

**Option B — AWS Console (Step-by-Step):**
1. Go to **AWS Console** → Search **"Lambda"** → Click **Lambda**
2. Click the orange **"Create function"** button
3. **Create function page:**
   - Select ✅ **Author from scratch**
   - Function name: `imageProcessor`
   - Runtime: **Node.js 20.x**
   - Architecture: **x86_64**
4. **Permissions:**
   - Expand **"Change default execution role"**
   - Select ✅ **Use an existing role**
   - Existing role: **image-processor-lambda-role** (created in Step 3)
5. Click **"Create function"** ✅
6. **Upload the code (zip file):**
   - First, on your local machine, prepare the zip:
     ```bash
     cd src/image-processor
     npm install
     npm install --os=linux --cpu=x64 sharp
     zip -r ../../image-processor.zip .
     ```
   - In Lambda Console → **Code** tab → Click **"Upload from"** → **".zip file"**
   - Browse and select `image-processor.zip`
   - Click **"Save"**
7. **Configure General Settings:**
   - Go to **"Configuration"** tab → **"General configuration"** → Click **"Edit"**
   - Memory: `1024` MB
   - Timeout: `1` min `0` sec
   - Click **"Save"** ✅
8. **Add Environment Variables:**
   - Go to **"Configuration"** tab → **"Environment variables"** → Click **"Edit"**
   - Click **"Add environment variable"**:
     | Key | Value |
     |-----|-------|
     | `PROCESSED_BUCKET` | `my-app-processed` |
     | `METADATA_TABLE` | `image-metadata` |
   - Click **"Save"** ✅

---

### Step 6: Configure S3 Event Notification (Trigger Lambda on Upload)

**Option A — AWS Console (Step-by-Step):**

**Method 1 — From Lambda Console (Easiest):**
1. Go to **Lambda Console** → Click on **imageProcessor** function
2. In the **"Function overview"** diagram at the top, click **"+ Add trigger"**
3. **Trigger configuration:**
   - Select source: **S3**
   - Bucket: **my-app-uploads**
   - Event types: ✅ **All object create events** (`s3:ObjectCreated:*`)
   - Prefix: _(leave empty)_
   - Suffix: `.jpg`
   - ✅ Check **"I acknowledge that using the same S3 bucket..."**
   - Click **"Add"** ✅
4. **Repeat for other file types:**
   - Click **"+ Add trigger"** again → S3 → same bucket → Suffix: `.png` → **"Add"**
   - Click **"+ Add trigger"** again → S3 → same bucket → Suffix: `.jpeg` → **"Add"**
   - Click **"+ Add trigger"** again → S3 → same bucket → Suffix: `.webp` → **"Add"**
5. You should now see **4 S3 triggers** in the Function overview diagram

**Method 2 — From S3 Console:**
1. Go to **S3 Console** → Click on **my-app-uploads** bucket
2. Go to **"Properties"** tab
3. Scroll down to **"Event notifications"** section
4. Click **"Create event notification"**
5. **Event notification settings:**
   - Event name: `ImageUploadTrigger-jpg`
   - Prefix: _(leave empty)_
   - Suffix: `.jpg`
6. **Event types:**
   - ✅ Check **"All object create events"** (`s3:ObjectCreated:*`)
7. **Destination:**
   - Select ✅ **Lambda function**
   - Lambda function: **imageProcessor**
8. Click **"Save changes"** ✅
9. Repeat for `.png`, `.jpeg`, `.webp` suffixes

**Option B — AWS CLI:**
```bash
# First, grant S3 permission to invoke the Lambda
aws lambda add-permission \
  --function-name imageProcessor \
  --statement-id s3-trigger \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::my-app-uploads \
  --source-account 123456789012

# Then configure the S3 event notification
aws s3api put-bucket-notification-configuration \
  --bucket my-app-uploads \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "Id": "ImageUploadTrigger",
        "LambdaFunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:imageProcessor",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {"Name": "suffix", "Value": ".jpg"},
              {"Name": "suffix", "Value": ".png"},
              {"Name": "suffix", "Value": ".jpeg"},
              {"Name": "suffix", "Value": ".webp"}
            ]
          }
        }
      }
    ]
  }'
```

**Option B — Terraform:**
```hcl
# terraform/s3-notifications.tf

resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".png"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}
```

**Option C — CDK (TypeScript):**
```typescript
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';

uploadBucket.addEventNotification(
  s3.EventType.OBJECT_CREATED,
  new s3n.LambdaDestination(imageProcessorFunction),
  { suffix: '.jpg' },
  { suffix: '.png' },
  { suffix: '.jpeg' },
  { suffix: '.webp' }
);
```

---

### Step 7: Test the Pipeline

**Option A — AWS Console (Step-by-Step):**

**Upload a test image:**
1. Go to **S3 Console** → Click **my-app-uploads** bucket
2. Click **"Upload"** button
3. Click **"Add files"** → Select a `.jpg` or `.png` image from your computer
4. Click **"Upload"** ✅
5. Wait **5-10 seconds** for Lambda to process

**Verify processed images were created:**
6. Go to **S3 Console** → Click **my-app-processed** bucket
7. You should see **3 folders**:
   ```
   📁 thumbnail/    → 150x150 version
   📁 medium/       → 600x600 version
   📁 large/        → 1200x1200 version
   ```
8. Click into each folder to see the resized image files

**Verify DynamoDB metadata:**
9. Go to **DynamoDB Console** → Click **"Tables"** → Click **image-metadata**
10. Click **"Explore table items"** button
11. You should see a record with:
    - `imageId`: your filename
    - `status`: `completed`
    - `originalWidth`, `originalHeight`: original dimensions
    - `processedFiles`: array of 3 resized versions

**Check Lambda logs:**
12. Go to **Lambda Console** → Click **imageProcessor**
13. Click **"Monitor"** tab → Click **"View CloudWatch Logs"**
14. Click the latest log stream
15. You should see logs like:
    ```
    Processing: my-app-uploads/test-photo.jpg (2456789 bytes)
    Downloaded: test-photo.jpg (2456789 bytes)
    Original: 4032x3024, format: jpeg
    Uploaded: thumbnail/test-photo.jpg (8432 bytes)
    Uploaded: medium/test-photo.jpg (45210 bytes)
    Uploaded: large/test-photo.jpg (156780 bytes)
    ✅ Successfully processed: test-photo.jpg
    ```

**Test with Lambda Test Event (without uploading to S3):**
16. Go to **Lambda Console** → Click **imageProcessor** → **"Test"** tab
17. Click **"Create new event"**
18. Event name: `testS3Upload`
19. Template: Search for **"s3-put"** → Select **Amazon S3 Put**
20. Modify the JSON — change bucket name to `my-app-uploads` and key to an existing file
21. Click **"Test"** → Check the execution result

**Option B — AWS CLI:**
```bash
# Upload a test image
aws s3 cp test-photo.jpg s3://my-app-uploads/test-photo.jpg

# Wait a few seconds for Lambda to process...

# Check processed bucket — should have 3 resized versions
aws s3 ls s3://my-app-processed/thumbnail/
aws s3 ls s3://my-app-processed/medium/
aws s3 ls s3://my-app-processed/large/

# Check DynamoDB metadata
aws dynamodb get-item \
  --table-name image-metadata \
  --key '{"imageId": {"S": "test-photo_jpg"}}'

# Check Lambda logs
aws logs tail /aws/lambda/imageProcessor --since 5m
```

**Expected DynamoDB metadata record:**
```json
{
  "imageId": "test-photo_jpg",
  "originalKey": "test-photo.jpg",
  "originalSize": 2456789,
  "originalWidth": 4032,
  "originalHeight": 3024,
  "originalFormat": "jpeg",
  "processedFiles": [
    { "size": "thumbnail", "key": "thumbnail/test-photo.jpg", "bytes": 8432 },
    { "size": "medium", "key": "medium/test-photo.jpg", "bytes": 45210 },
    { "size": "large", "key": "large/test-photo.jpg", "bytes": 156780 }
  ],
  "processedAt": "2026-03-12T10:30:00.000Z",
  "status": "completed"
}
```

---

### Step 8: Add Error Handling with SNS Notification (Optional)

**Option A — AWS Console (Step-by-Step):**

**Create SNS Topic:**
1. Go to **AWS Console** → Search **"SNS"** → Click **Simple Notification Service**
2. In the left sidebar, click **"Topics"**
3. Click **"Create topic"**
4. **Details:**
   - Type: **Standard**
   - Name: `image-processing-failures`
5. Click **"Create topic"** ✅

**Add Email Subscription:**
6. On the topic page, click **"Create subscription"**
7. **Details:**
   - Protocol: **Email**
   - Endpoint: `your-email@example.com`
8. Click **"Create subscription"** ✅
9. **Check your email inbox** → Click the **"Confirm subscription"** link in the email from AWS
10. Status should change to **"Confirmed"**

**Configure Lambda Failure Destination:**
11. Go to **Lambda Console** → Click **imageProcessor**
12. Go to **"Configuration"** tab → **"Destinations"** in the left sidebar
13. Click **"Add destination"**
14. **Destination configuration:**
    - Condition: **On failure**
    - Destination type: **SNS topic**
    - Destination: **image-processing-failures**
15. Click **"Save"** ✅

**Configure Retry Attempts:**
16. Go to **"Configuration"** tab → **"Asynchronous invocation"** → Click **"Edit"**
17. Maximum retry attempts: `2`
18. Maximum event age: `1 hour`
19. Click **"Save"** ✅

> Now when image processing fails after 2 retries, you'll receive an email with the error details.

**Option B — AWS CLI:**
```bash
# Create SNS topic for failures
aws sns create-topic --name image-processing-failures
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:image-processing-failures \
  --protocol email \
  --notification-endpoint your-email@example.com

# Configure Lambda Destination for failures
aws lambda put-function-event-invoke-config \
  --function-name imageProcessor \
  --maximum-retry-attempts 2 \
  --on-failure Destination=arn:aws:sns:us-east-1:123456789012:image-processing-failures
```

---

### Step 9: Add Lifecycle Rules (Cost Optimization)

**Option A — AWS Console (Step-by-Step):**

**Rule 1 — Delete originals after 30 days:**
1. Go to **S3 Console** → Click **my-app-uploads** bucket
2. Go to **"Management"** tab
3. Click **"Create lifecycle rule"**
4. **Lifecycle rule configuration:**
   - Rule name: `DeleteOriginalAfter30Days`
   - Choose a rule scope: ✅ **Apply to all objects in the bucket**
   - ✅ Check **"I acknowledge that this rule will apply to all objects"**
5. **Lifecycle rule actions:**
   - ✅ Check **"Expire current versions of objects"**
6. **Expire current versions of objects:**
   - Days after object creation: `30`
7. Click **"Create rule"** ✅

**Rule 2 — Archive processed images to Glacier after 90 days:**
8. Go to **S3 Console** → Click **my-app-processed** bucket
9. Go to **"Management"** tab → Click **"Create lifecycle rule"**
10. **Lifecycle rule configuration:**
    - Rule name: `ArchiveAfter90Days`
    - Choose a rule scope: ✅ **Apply to all objects in the bucket**
    - ✅ Check acknowledgment
11. **Lifecycle rule actions:**
    - ✅ Check **"Transition current versions of objects between storage classes"**
12. **Transition current versions:**
    - Choose storage class transitions:
      | Storage class | Days after object creation |
      |---|---|
      | **Glacier Flexible Retrieval** | `90` |
13. Click **"Create rule"** ✅

> 💰 **Cost savings:** Glacier storage costs ~$0.004/GB/month vs $0.023/GB for Standard — **83% cheaper!**

**Option B — AWS CLI:**
```bash
# Auto-delete original uploads after 30 days (processed versions are kept)
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-app-uploads \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "DeleteOriginalAfter30Days",
        "Status": "Enabled",
        "Filter": {},
        "Expiration": { "Days": 30 }
      }
    ]
  }'

# Move processed images to Glacier after 90 days
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-app-processed \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "ArchiveAfter90Days",
        "Status": "Enabled",
        "Filter": {},
        "Transitions": [
          { "Days": 90, "StorageClass": "GLACIER" }
        ]
      }
    ]
  }'
```

---

### Complete Architecture Summary

```
                          ┌──────────────────────────┐
                          │   my-app-uploads (S3)     │
  User uploads image ───► │   s3:ObjectCreated:*      │
                          └──────────┬───────────────┘
                                     │ triggers
                                     ▼
                          ┌──────────────────────────┐
                          │   Lambda: imageProcessor  │
                          │   - Downloads original    │
                          │   - Resizes to 3 sizes    │
                          │   - Memory: 1024MB        │
                          │   - Timeout: 60s          │
                          └────┬──────────┬──────────┘
                               │          │
                    ┌──────────▼──┐  ┌────▼───────────────┐
                    │ my-app-     │  │ image-metadata      │
                    │ processed   │  │ (DynamoDB)          │
                    │ (S3)        │  │ - dimensions        │
                    │ /thumbnail/ │  │ - file sizes        │
                    │ /medium/    │  │ - status            │
                    │ /large/     │  │ - processedAt       │
                    └─────────────┘  └─────────────────────┘
```

---

## Use Case 4: Scheduled Tasks (Cron Jobs)

**Problem:** Run periodic tasks like cleanup, reporting, or data sync without a server.

**Architecture:**
```
EventBridge Scheduled Rule → Lambda → DynamoDB / S3 / SES
```

**Steps:**
1. Create a Lambda function for the periodic task (e.g., delete expired sessions, generate daily report)
2. Create an EventBridge rule with a schedule expression:
   - `rate(1 hour)` — run every hour
   - `rate(5 minutes)` — run every 5 minutes
   - `cron(0 9 * * ? *)` — run daily at 9:00 AM UTC
   - `cron(0 0 1 * ? *)` — run on the 1st of every month
3. Set the Lambda function as the rule's target
4. Add CloudWatch Alarms for invocation errors
5. Use environment variables for configurable thresholds

**AWS Services:** EventBridge, Lambda, CloudWatch

**Key Code Pattern:**
```javascript
export const handler = async (event) => {
  console.log("Scheduled task triggered at:", new Date().toISOString());

  // Example: Delete expired sessions older than 24 hours
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const params = {
    TableName: process.env.SESSIONS_TABLE,
    FilterExpression: "expiresAt < :cutoff",
    ExpressionAttributeValues: { ":cutoff": { S: cutoff } }
  };

  const { Items } = await ddbClient.send(new ScanCommand(params));
  // Delete each expired item...
};
```

---

## Use Case 5: Real-Time Data Transformation (DynamoDB Streams ETL)

**Problem:** React to database changes in real-time for analytics, search indexing, or notifications.

**Architecture:**
```
DynamoDB (source) → DynamoDB Stream → Lambda → OpenSearch / S3 / SNS
```

**Steps:**
1. Enable DynamoDB Streams on your table (Stream View Type: `NEW_AND_OLD_IMAGES`)
2. Create a Lambda function with an Event Source Mapping to the stream
3. Lambda processes each stream record:
   - Detect event type: `INSERT`, `MODIFY`, `REMOVE`
   - Transform data as needed
   - Push to target: OpenSearch for search, S3 for analytics, SNS for notifications
4. Configure batch settings: `BatchSize: 10`, `MaximumRetryAttempts: 3`
5. Set up a DLQ for records that fail processing

**AWS Services:** DynamoDB Streams, Lambda, OpenSearch/S3/SNS

**Key Code Pattern:**
```javascript
export const handler = async (event) => {
  for (const record of event.Records) {
    console.log("Event type:", record.eventName); // INSERT, MODIFY, REMOVE

    if (record.eventName === "INSERT") {
      const newItem = unmarshall(record.dynamodb.NewImage);
      // Index in OpenSearch, send notification, etc.
    } else if (record.eventName === "MODIFY") {
      const oldItem = unmarshall(record.dynamodb.OldImage);
      const newItem = unmarshall(record.dynamodb.NewImage);
      // Compare and react to changes
    } else if (record.eventName === "REMOVE") {
      const deletedItem = unmarshall(record.dynamodb.OldImage);
      // Clean up related data
    }
  }
};
```

---

## Use Case 6: Custom API Authorizer (JWT Validation)

**Problem:** Validate authentication tokens before requests reach your backend Lambda.

**Architecture:**
```
Client → API Gateway → Lambda Authorizer (validate JWT) → Backend Lambda
```

**Steps:**
1. Create a Lambda Authorizer function:
   - Extract `Authorization` header from the event
   - Decode and verify JWT token (using `jsonwebtoken` library)
   - Return an IAM Allow/Deny policy document
2. In API Gateway, create a Lambda Authorizer (Token-based)
3. Attach the authorizer to protected API routes
4. Enable authorization caching (e.g., 300 seconds TTL) to reduce invocations
5. Pass user context (userId, role) to downstream Lambdas via `context`

**AWS Services:** API Gateway, Lambda, Cognito (optional)

**Key Code Pattern:**
```javascript
import jwt from "jsonwebtoken";

export const handler = async (event) => {
  const token = event.authorizationToken?.replace("Bearer ", "");

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    return {
      principalId: decoded.sub,
      policyDocument: {
        Version: "2012-10-17",
        Statement: [{
          Action: "execute-api:Invoke",
          Effect: "Allow",
          Resource: event.methodArn
        }]
      },
      context: { userId: decoded.sub, role: decoded.role }
    };
  } catch (err) {
    throw new Error("Unauthorized");
  }
};
```

---

## Use Case 7: Real-Time Notifications System

**Problem:** Send emails, SMS, or Slack messages when specific events occur.

**Architecture:**
```
Lambda (trigger) → SNS Topic → Email / SMS / HTTP (Slack)
```

**Steps:**
1. Create an SNS topic with subscribers:
   - Email subscriptions for alerts
   - SMS subscriptions for critical notifications
   - HTTPS endpoint for Slack webhook integration
2. Lambda publishes to SNS when conditions are met (new order, error threshold, etc.)
3. Use SNS **filter policies** to route messages to specific subscribers
4. For Slack: create a secondary Lambda subscribed to SNS that posts to Slack Webhook
5. Add message attributes for filtering and routing

**AWS Services:** Lambda, SNS, SES (for rich emails)

**Key Code Pattern:**
```javascript
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const snsClient = new SNSClient({});

export const handler = async (event) => {
  // Send notification when a new order is placed
  await snsClient.send(new PublishCommand({
    TopicArn: process.env.ORDER_NOTIFICATIONS_TOPIC,
    Subject: "New Order Placed",
    Message: JSON.stringify({
      orderId: event.detail.orderId,
      userName: event.detail.userName,
      totalPrice: event.detail.totalPrice,
      orderDate: new Date().toISOString()
    }),
    MessageAttributes: {
      orderType: { DataType: "String", StringValue: "new_order" }
    }
  }));
};
```

---

## Use Case 8: CloudFront Lambda@Edge (CDN Customization)

**Problem:** Modify HTTP requests/responses at the CDN edge for A/B testing, redirects, security headers.

**Architecture:**
```
Client → CloudFront → Lambda@Edge → Origin (S3 / ALB / API Gateway)
```

**Steps:**
1. Create a Lambda function in **us-east-1** (required for Lambda@Edge)
2. Choose trigger point:
   - **Viewer Request** — auth checks, redirects, A/B testing (before cache)
   - **Origin Request** — URL rewriting, dynamic origin selection (after cache miss)
   - **Origin Response** — add/modify headers before caching
   - **Viewer Response** — add security headers (CSP, HSTS, X-Frame-Options)
3. Associate Lambda with a CloudFront distribution behavior
4. Deploy (propagation takes ~5–15 minutes across all edge locations)
5. Test with `curl -I` to verify response headers

**AWS Services:** CloudFront, Lambda@Edge

**Key Code Pattern (Security Headers):**
```javascript
export const handler = async (event) => {
  const response = event.Records[0].cf.response;
  const headers = response.headers;

  headers["strict-transport-security"] = [{ value: "max-age=63072000; includeSubdomains; preload" }];
  headers["x-content-type-options"] = [{ value: "nosniff" }];
  headers["x-frame-options"] = [{ value: "DENY" }];
  headers["content-security-policy"] = [{ value: "default-src 'self'" }];

  return response;
};
```

---

## Quick Comparison Table

| # | Use Case | Trigger Source | Target | Latency | Difficulty |
|---|---|---|---|---|---|
| 1 | ✅ REST API | API Gateway | DynamoDB | Real-time | ⭐ Easy |
| 2 | ✅ Event Processing | EventBridge/SQS | DynamoDB | Near real-time | ⭐⭐ Medium |
| 3 | Image Processing | S3 Event | S3 + DynamoDB | Seconds | ⭐⭐ Medium |
| 4 | Cron Jobs | EventBridge Schedule | Any | Scheduled | ⭐ Easy |
| 5 | DynamoDB Streams ETL | DynamoDB Streams | OpenSearch/S3 | Near real-time | ⭐⭐ Medium |
| 6 | Custom Authorizer | API Gateway | IAM Policy | Real-time | ⭐⭐ Medium |
| 7 | Notifications | Lambda → SNS | Email/SMS/Slack | Real-time | ⭐ Easy |
| 8 | Edge Computing | CloudFront | Origin | Milliseconds | ⭐⭐⭐ Advanced |

---

## 👉 Next Step

**Tell me which use case number(s) you want to implement, and I'll build it step-by-step in this project!**
