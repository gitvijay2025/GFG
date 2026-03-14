import { PutItemCommand, QueryCommand, ScanCommand } from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";
import { ddbClient } from "./ddbClient.mjs";

//exports.handler = async function(event) {
export const handler = async (event) => {
  console.log("request:", JSON.stringify(event, undefined, 2));

  // Detect event source with detailed logging
  console.log("event.Records:", event.Records);
  console.log("event.detail-type:", event['detail-type']);
  console.log("event.httpMethod:", event.httpMethod);

  // This is the decision logic:
  if (event.Records && event.Records.length > 0) {
    // SQS sent this event → call sqsInvocation() → createOrder()
    console.log("Detected SQS invocation");
    await sqsInvocation(event);
  }
  else if (event['detail-type'] !== undefined) {
    // EventBridge sent this directly → call eventBridgeInvocation() → createOrder()
    console.log("Detected EventBridge invocation");
    await eventBridgeInvocation(event);
  } else if (event.httpMethod) {
    // API Gateway sent this → call apiGatewayInvocation() → getOrder/getAllOrders
    console.log("Detected API Gateway invocation");
    return await apiGatewayInvocation(event);
  } else {
    console.log("Unknown event source. Full event:", JSON.stringify(event));
    throw new Error("Unknown event source - not SQS, EventBridge, or API Gateway");
  }
};

const sqsInvocation = async (event) => {
  console.log(`sqsInvocation function. event : "${JSON.stringify(event)}"`);

  for (const record of event.Records) {
    console.log('Record body raw: ', record.body);

    const checkoutEventRequest = JSON.parse(record.body);
    console.log('Parsed SQS body: ', JSON.stringify(checkoutEventRequest));
    console.log('detail field: ', JSON.stringify(checkoutEventRequest.detail));

    // EventBridge wraps payload in "detail". If detail exists, use it.
    // If not, the body itself might be the order data.
    const orderData = checkoutEventRequest.detail || checkoutEventRequest;
    console.log('orderData to save: ', JSON.stringify(orderData));

    await createOrder(orderData);
  }
}

const eventBridgeInvocation = async (event) => {
  console.log(`eventBridgeInvocation function. event : "${event}"`);

  // create order item into db
  await createOrder(event.detail);
}

const createOrder = async (basketCheckoutEvent) => {
  try {
    console.log(`createOrder function. event : "${basketCheckoutEvent}"`);

    // set orderDate for SK of order dynamodb
    const orderDate = new Date().toISOString();
    basketCheckoutEvent.orderDate = orderDate;
    console.log(basketCheckoutEvent);

    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME,
      Item: marshall(basketCheckoutEvent || {})
    };

    const createResult = await ddbClient.send(new PutItemCommand(params));
    console.log(createResult);
    return createResult;

  } catch (e) {
    console.error(e);
    throw e;
  }
}

const apiGatewayInvocation = async (event) => {
  // GET /order	
  // GET /order/{userName}
  let body;

  // Parse path segments for {proxy+} compatibility
  const pathSegments = event.path.split("/");
  const pathParam = pathSegments[2] || null;

  try {
    switch (event.httpMethod) {
      case "GET":
        if (pathParam) {
          body = await getOrder(pathParam, event);
        } else {
          body = await getAllOrders();
        }
        break;
      default:
        throw new Error(`Unsupported route: "${event.httpMethod}"`);
    }

    console.log(body);
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: `Successfully finished operation: "${event.httpMethod}"`,
        body: body
      })
    };
  }
  catch (e) {
    console.error(e);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: "Failed to perform operation.",
        errorMsg: e.message,
        errorStack: e.stack,
      })
    };
  }
}

const getOrder = async (userName, event) => {
  console.log("getOrder");

  try {
    // expected request : xxx/order/swn?orderDate=timestamp
    const orderDate = event.queryStringParameters?.orderDate;

    const params = {
      KeyConditionExpression: orderDate 
        ? "userName = :userName and orderDate = :orderDate"
        : "userName = :userName",
      ExpressionAttributeValues: orderDate
        ? {
            ":userName": { S: userName },
            ":orderDate": { S: orderDate }
          }
        : {
            ":userName": { S: userName }
          },
      TableName: process.env.DYNAMODB_TABLE_NAME
    };

    const { Items } = await ddbClient.send(new QueryCommand(params));

    console.log(Items);
    return Items.map((item) => unmarshall(item));
  } catch (e) {
    console.error(e);
    throw e;
  }
}

const getAllOrders = async () => {
  console.log("getAllOrders");
  try {
    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME
    };

    const { Items } = await ddbClient.send(new ScanCommand(params));

    console.log(Items);
    return (Items) ? Items.map((item) => unmarshall(item)) : {};

  } catch (e) {
    console.error(e);
    throw e;
  }
}