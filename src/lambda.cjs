const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { GetObjectCommand, HeadObjectCommand, S3Client } = require("@aws-sdk/client-s3");

const s3 = new S3Client({ region: process.env.AWS_REGION });
const dynamodb = new DynamoDBClient({ region: process.env.AWS_REGION });

const metadataTableName = process.env.METADATA_TABLE_NAME;
const MAX_FILE_PREVIEW_SIZE = 1024; // 1KB for preview
const TEXT_LIKE_CONTENT_TYPES = ["text/", "application/json", "application/xml"];

// Structured logging
const logger = {
  info: (message, data = {}) =>
    console.log(JSON.stringify({ level: "INFO", message, ...data, timestamp: new Date().toISOString() })),
  warn: (message, data = {}) =>
    console.warn(JSON.stringify({ level: "WARN", message, ...data, timestamp: new Date().toISOString() })),
  error: (message, error, data = {}) =>
    console.error(
      JSON.stringify({
        level: "ERROR",
        message,
        error: error?.message || String(error),
        ...data,
        timestamp: new Date().toISOString(),
      }),
    ),
};

/**
 * Check if content type is text-like
 */
function isTextLikeContent(contentType = "") {
  return TEXT_LIKE_CONTENT_TYPES.some((type) => contentType.startsWith(type));
}

/**
 * Safely extract file preview from body
 */
async function extractFilePreview(body, contentType) {
  try {
    if (!body || !isTextLikeContent(contentType)) {
      return "[binary content]";
    }

    const text = await body.transformToString("utf-8");
    return text.slice(0, MAX_FILE_PREVIEW_SIZE);
  } catch (error) {
    logger.warn("Failed to extract file preview", { contentType, error: error?.message });
    return "[preview unavailable]";
  }
}

/**
 * Process a single S3 record
 */
async function processSingleRecord(record) {
  const bucket = record.s3.bucket.name;
  const encodedKey = record.s3.object.key;
  let key;

  try {
    key = decodeURIComponent(encodedKey.replace(/\+/g, " "));
  } catch (error) {
    throw new Error(`Failed to decode S3 key: ${error.message}`);
  }

  logger.info("Processing S3 object", { bucket, key });

  let metadataResponse;
  let objectResponse;

  try {
    metadataResponse = await s3.send(
      new HeadObjectCommand({
        Bucket: bucket,
        Key: key,
      }),
    );
  } catch (error) {
    throw new Error(`Failed to get object metadata: ${error.message}`);
  }

  try {
    objectResponse = await s3.send(
      new GetObjectCommand({
        Bucket: bucket,
        Key: key,
      }),
    );
  } catch (error) {
    throw new Error(`Failed to get object body: ${error.message}`);
  }

  const filePreview = await extractFilePreview(objectResponse.Body, metadataResponse.ContentType);
  const processedAt = new Date().toISOString();

  // Write metadata to DynamoDB
  try {
    await dynamodb.send(
      new PutItemCommand({
        TableName: metadataTableName,
        Item: {
          object_id: { S: `${bucket}#${key}` },
          processed_at: { S: processedAt },
          bucket: { S: bucket },
          object_key: { S: key },
          content_type: { S: metadataResponse.ContentType || "unknown" },
          content_length: { N: String(metadataResponse.ContentLength || 0) },
          e_tag: { S: metadataResponse.ETag || "" },
          last_modified: {
            S: metadataResponse.LastModified ? metadataResponse.LastModified.toISOString() : "",
          },
          user_metadata: { S: JSON.stringify(metadataResponse.Metadata || {}) },
          file_preview: { S: filePreview },
        },
      }),
    );
  } catch (error) {
    throw new Error(`Failed to write metadata to DynamoDB: ${error.message}`);
  }

  return {
    bucket,
    key,
    processedAt,
    contentType: metadataResponse.ContentType,
    contentLength: metadataResponse.ContentLength,
    eTag: metadataResponse.ETag,
    lastModified: metadataResponse.LastModified
      ? metadataResponse.LastModified.toISOString()
      : undefined,
    userMetadata: metadataResponse.Metadata || {},
    filePreview,
  };
}

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
  // Validate environment
  if (!metadataTableName) {
    const error = "METADATA_TABLE_NAME environment variable is not set";
    logger.error(error, new Error(error));
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Configuration error" }),
    };
  }

  // Validate event
  if (!event.Records || event.Records.length === 0) {
    logger.warn("No S3 records in event");
    return {
      statusCode: 400,
      body: JSON.stringify({ error: "No S3 records found" }),
    };
  }

  logger.info("Processing batch", { recordCount: event.Records.length });

  const results = [];
  const errors = [];

  // Process records with error handling per record
  for (let i = 0; i < event.Records.length; i++) {
    try {
      const result = await processSingleRecord(event.Records[i]);
      results.push(result);
      logger.info("Successfully processed record", { recordIndex: i, key: result.key });
    } catch (error) {
      const errorMsg = error?.message || String(error);
      logger.error("Failed to process record", error, { recordIndex: i });
      errors.push({
        recordIndex: i,
        error: errorMsg,
      });
    }
  }

  logger.info("Batch processing complete", {
    successCount: results.length,
    errorCount: errors.length,
  });

  // Return appropriate status
  const hasErrors = errors.length > 0;
  return {
    statusCode: hasErrors ? 207 : 200, // 207 Multi-Status if partial success
    body: JSON.stringify({
      message: "Metadata processing completed",
      processed: results.length,
      failed: errors.length,
      objects: results,
      errors: hasErrors ? errors : undefined,
    }),
  };
};
