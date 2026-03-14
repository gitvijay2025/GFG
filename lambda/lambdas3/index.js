import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { marshall } from "@aws-sdk/util-dynamodb";
import sharp from "sharp";

const s3Client = new S3Client({ region: process.env.AWS_REGION || "ap-south-1" });
const ddbClient = new DynamoDBClient({ region: process.env.AWS_REGION || "ap-south-1" });

/**
 * Extracts S3 event records from various event sources:
 * - Direct S3 notifications
 * - SQS-wrapped S3 events (S3 → SQS → Lambda)
 * - SNS-wrapped S3 events (S3 → SNS → Lambda)
 */
function extractS3Records(event) {
  // Direct S3 event
  if (Array.isArray(event.Records) && event.Records[0]?.s3) {
    return event.Records;
  }

  // SQS-wrapped or SNS-wrapped S3 events
  if (Array.isArray(event.Records)) {
    return event.Records.flatMap((record) => {
      let body = record.body || record.Sns?.Message;
      if (typeof body === "string") {
        try {
          body = JSON.parse(body);
        } catch {
          return [];
        }
      }
      return Array.isArray(body?.Records) ? body.Records.filter((r) => r.s3) : [];
    });
  }

  return [];
}

export const handler = async (event) => {
  console.log("S3 Event received:", JSON.stringify(event, null, 2));

  // Extract S3 records from various event sources
  const s3Records = extractS3Records(event);
  if (s3Records.length === 0) {
    console.warn("No S3 records found in event");
    return { statusCode: 200, body: "No records to process" };
  }

  for (const record of s3Records) {
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