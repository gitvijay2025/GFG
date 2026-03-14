# Apache Kafka with Node.js — Basic to Advanced Guide

> A comprehensive hands-on guide covering all Kafka use cases with Node.js using **KafkaJS**.

---

## Table of Contents

1. [Prerequisites & Setup](#1-prerequisites--setup)
2. [Project Initialization](#2-project-initialization)
3. [Basic Level](#3-basic-level)
   - 3.1 Simple Producer
   - 3.2 Simple Consumer
   - 3.3 Consumer Groups
4. [Intermediate Level](#4-intermediate-level)
   - 4.1 Keyed Messages (Partitioning)
   - 4.2 Batch Producing
   - 4.3 Multiple Topics & Consumers
   - 4.4 Manual Offset Management
   - 4.5 Retry & Error Handling
5. [Advanced Level](#5-advanced-level)
   - 5.1 Exactly-Once Semantics (Transactions)
   - 5.2 Dead Letter Queue (DLQ)
   - 5.3 Event Sourcing Pattern
   - 5.4 Stream Processing (Real-time Aggregation)
   - 5.5 Schema Registry (Avro Serialization)
   - 5.6 Admin Client — Topic Management
   - 5.7 Real-time Notification System (Express + Kafka + SSE)
6. [Docker Setup — Complete Containerized Environment](#6-docker-setup--complete-containerized-environment)
   - 6.1 Dockerfile (Production)
   - 6.2 `.dockerignore`
   - 6.3 Dockerfile for Development (hot-reload)
   - 6.4 Docker Compose — Full Stack
   - 6.5 Updated `config.js` (Docker-aware)
   - 6.6 Environment File
   - 6.7 Docker Commands — Complete Reference
   - 6.8 Network Architecture Diagram
7. [Project Structure](#7-project-structure)
8. [Quick Reference & Cheat Sheet](#8-quick-reference--cheat-sheet)

---

## 1. Prerequisites & Setup

### Install Required Software

```bash
# Node.js (v18+ recommended)
node -v

# Docker & Docker Compose (for Kafka cluster)
docker --version
docker compose version
```

### Start Kafka via Docker

Create a `docker-compose.yml` file (see [Section 6](#6-docker-compose--kafka-cluster)) and run:

```bash
docker compose up -d
```

This starts:
- **Zookeeper** on port `2181`
- **Kafka Broker 1** on port `9092`
- **Kafka Broker 2** on port `9093`
- **Kafka UI** on port `8080` (open http://localhost:8080)

---

## 2. Project Initialization

```bash
mkdir kafka-nodejs-lab && cd kafka-nodejs-lab

npm init -y

# Core dependency
npm install kafkajs

# Additional dependencies (for advanced examples)
npm install express uuid @kafkajs/confluent-schema-registry avsc dotenv
```

Create a shared config file:

### `config.js`

```js
// config.js
const { Kafka, logLevel } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'kafka-nodejs-lab',
  brokers: ['localhost:9092', 'localhost:9093'],
  logLevel: logLevel.WARN,
  retry: {
    initialRetryTime: 300,
    retries: 10,
  },
});

module.exports = { kafka };
```

---

## 3. Basic Level

---

### 3.1 Simple Producer

> **Use Case:** Send a single message to a Kafka topic.

#### `basic/producer.js`

```js
const { kafka } = require('../config');

const producer = kafka.producer();

async function run() {
  await producer.connect();
  console.log('✅ Producer connected');

  const result = await producer.send({
    topic: 'basic-topic',
    messages: [
      {
        value: JSON.stringify({
          message: 'Hello Kafka!',
          timestamp: new Date().toISOString(),
        }),
      },
    ],
  });

  console.log('📤 Message sent:', JSON.stringify(result, null, 2));
  await producer.disconnect();
}

run().catch(console.error);
```

**Run:**
```bash
node basic/producer.js
```

**Key Concepts:**
- `producer.connect()` — establishes connection to the broker
- `producer.send()` — sends messages to a topic
- Messages are JSON serialized with `JSON.stringify()`

---

### 3.2 Simple Consumer

> **Use Case:** Read messages from a Kafka topic.

#### `basic/consumer.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({ groupId: 'basic-group' });

async function run() {
  await consumer.connect();
  console.log('✅ Consumer connected');

  await consumer.subscribe({ topic: 'basic-topic', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const value = JSON.parse(message.value.toString());
      console.log(`📥 Received:`, {
        topic,
        partition,
        offset: message.offset,
        value,
      });
    },
  });
}

run().catch(console.error);

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Disconnecting consumer...');
  await consumer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node basic/consumer.js
```

**Key Concepts:**
- `groupId` — identifies the consumer group
- `fromBeginning: true` — reads all messages from the start
- `eachMessage` — callback invoked for every message
- Graceful shutdown on `SIGINT` (Ctrl+C)

---

### 3.3 Consumer Groups

> **Use Case:** Distribute message processing across multiple consumer instances (horizontal scaling).

#### `basic/consumer-group.js`

```js
const { kafka } = require('../config');

// Accept consumer ID from command line
const consumerId = process.argv[2] || '1';

const consumer = kafka.consumer({ groupId: 'my-consumer-group' });

async function run() {
  await consumer.connect();
  console.log(`✅ Consumer-${consumerId} connected (group: my-consumer-group)`);

  await consumer.subscribe({ topic: 'basic-topic', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      console.log(`[Consumer-${consumerId}] partition=${partition} offset=${message.offset} value=${message.value.toString()}`);
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  process.exit(0);
});
```

**Run (open 3 terminals):**
```bash
# Terminal 1
node basic/consumer-group.js 1

# Terminal 2
node basic/consumer-group.js 2

# Terminal 3 — produce messages
node basic/producer.js
```

**Key Concepts:**
- Consumers in the same `groupId` share the load
- Kafka assigns partitions to consumers automatically
- If one consumer dies, its partitions rebalance to others

---

## 4. Intermediate Level

---

### 4.1 Keyed Messages (Partitioning)

> **Use Case:** Ensure all messages with the same key go to the same partition (e.g., all orders from one user go to one consumer).

#### `intermediate/keyed-producer.js`

```js
const { kafka } = require('../config');

const producer = kafka.producer();

async function run() {
  await producer.connect();

  const users = ['user-101', 'user-202', 'user-303'];

  for (let i = 0; i < 10; i++) {
    const userId = users[i % users.length];
    const result = await producer.send({
      topic: 'orders-topic',
      messages: [
        {
          key: userId,  // Messages with same key → same partition
          value: JSON.stringify({
            userId,
            orderId: `ORD-${1000 + i}`,
            amount: Math.floor(Math.random() * 500) + 10,
            createdAt: new Date().toISOString(),
          }),
        },
      ],
    });
    console.log(`📤 Order sent for ${userId} → partition ${result[0].partition}`);
  }

  await producer.disconnect();
}

run().catch(console.error);
```

**Key Concepts:**
- `key` determines which partition the message goes to
- Same key = same partition = ordered processing for that key
- Use this for user-specific, session-specific, or entity-specific ordering

---

### 4.2 Batch Producing

> **Use Case:** Send multiple messages in one call for higher throughput.

#### `intermediate/batch-producer.js`

```js
const { kafka } = require('../config');
const { CompressionTypes } = require('kafkajs');

const producer = kafka.producer({
  allowAutoTopicCreation: true,
  transactionTimeout: 30000,
});

async function run() {
  await producer.connect();

  // Generate 1000 messages
  const messages = Array.from({ length: 1000 }, (_, i) => ({
    key: `device-${i % 10}`,
    value: JSON.stringify({
      deviceId: `device-${i % 10}`,
      temperature: (20 + Math.random() * 15).toFixed(2),
      humidity: (40 + Math.random() * 40).toFixed(2),
      timestamp: Date.now(),
    }),
  }));

  // Send in batches
  const BATCH_SIZE = 100;
  for (let i = 0; i < messages.length; i += BATCH_SIZE) {
    const batch = messages.slice(i, i + BATCH_SIZE);
    await producer.send({
      topic: 'iot-sensor-data',
      compression: CompressionTypes.GZIP,  // Compress for efficiency
      messages: batch,
    });
    console.log(`📤 Batch sent: messages ${i + 1} to ${i + batch.length}`);
  }

  console.log('✅ All 1000 messages sent');
  await producer.disconnect();
}

run().catch(console.error);
```

**Key Concepts:**
- Send arrays of messages in one `send()` call
- Use `CompressionTypes.GZIP` or `SNAPPY` for large payloads
- Batch sending dramatically improves throughput

---

### 4.3 Multiple Topics & Consumers

> **Use Case:** One application subscribes to multiple topics with different processing logic.

#### `intermediate/multi-topic-consumer.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({ groupId: 'multi-topic-group' });

// Topic-specific handlers
const handlers = {
  'orders-topic': async (message) => {
    const order = JSON.parse(message.value.toString());
    console.log(`🛒 ORDER: ${order.orderId} from ${order.userId} — $${order.amount}`);
  },
  'iot-sensor-data': async (message) => {
    const reading = JSON.parse(message.value.toString());
    console.log(`🌡️ SENSOR: ${reading.deviceId} — temp=${reading.temperature}°C humidity=${reading.humidity}%`);
  },
  'notifications': async (message) => {
    const notif = JSON.parse(message.value.toString());
    console.log(`🔔 NOTIFICATION: [${notif.type}] ${notif.message}`);
  },
};

async function run() {
  await consumer.connect();

  // Subscribe to multiple topics
  await consumer.subscribe({ topics: ['orders-topic', 'iot-sensor-data', 'notifications'], fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const handler = handlers[topic];
      if (handler) {
        await handler(message);
      } else {
        console.log(`⚠️ No handler for topic: ${topic}`);
      }
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  process.exit(0);
});
```

---

### 4.4 Manual Offset Management

> **Use Case:** Control exactly when offsets are committed (e.g., only after successful DB write).

#### `intermediate/manual-offset-consumer.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({
  groupId: 'manual-offset-group',
  // Disable auto-commit
  autoCommit: false,
});

async function processAndSaveToDB(data) {
  // Simulate DB write (could fail)
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (Math.random() > 0.1) {
        resolve();
      } else {
        reject(new Error('DB write failed'));
      }
    }, 100);
  });
}

async function run() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'orders-topic', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message, heartbeat }) => {
      const order = JSON.parse(message.value.toString());

      try {
        // Process the message
        await processAndSaveToDB(order);

        // Only commit AFTER successful processing
        await consumer.commitOffsets([
          {
            topic,
            partition,
            offset: (parseInt(message.offset) + 1).toString(), // Next offset
          },
        ]);

        console.log(`✅ Processed & committed: offset=${message.offset}`);

        // Send heartbeat for long-running processing
        await heartbeat();
      } catch (error) {
        console.error(`❌ Failed at offset=${message.offset}: ${error.message}`);
        // Message will be re-delivered on restart since offset wasn't committed
      }
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  process.exit(0);
});
```

**Key Concepts:**
- `autoCommit: false` — you control when offsets are saved
- Commit only after successful processing → **at-least-once** delivery
- Use `heartbeat()` during long processing to avoid session timeout

---

### 4.5 Retry & Error Handling

> **Use Case:** Robust producer/consumer with retry logic and error handling.

#### `intermediate/resilient-producer.js`

```js
const { kafka } = require('../config');

const producer = kafka.producer({
  retry: {
    initialRetryTime: 100,
    retries: 8,
    maxRetryTime: 30000,
    factor: 2,         // Exponential backoff
    multiplier: 1.5,
  },
  idempotent: true,     // Prevent duplicate messages on retry
});

async function sendWithRetry(topic, messages, maxAttempts = 3) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await producer.send({ topic, messages });
      console.log(`✅ Sent on attempt ${attempt}`);
      return result;
    } catch (error) {
      console.error(`❌ Attempt ${attempt} failed: ${error.message}`);
      if (attempt === maxAttempts) {
        throw new Error(`Failed after ${maxAttempts} attempts: ${error.message}`);
      }
      // Exponential backoff
      await new Promise((r) => setTimeout(r, 1000 * Math.pow(2, attempt)));
    }
  }
}

async function run() {
  await producer.connect();

  // Producer events for monitoring
  producer.on('producer.connect', () => console.log('🔗 Producer connected'));
  producer.on('producer.disconnect', () => console.log('🔌 Producer disconnected'));

  try {
    await sendWithRetry('orders-topic', [
      { value: JSON.stringify({ orderId: 'ORD-999', amount: 150 }) },
    ]);
  } catch (error) {
    console.error('💀 Fatal:', error.message);
    // Send to DLQ, alert, etc.
  }

  await producer.disconnect();
}

run().catch(console.error);
```

### vj example with retry and Idempotent Processing so that same message will be consume again

```js

Idempotent Processing

const { kafka } = require('../config');

const consumer = kafka.consumer({
  groupId: 'manual-offset-group',
  autoCommit: false,
});

const MAX_RETRIES = 3;

// Simulated DB for processed message IDs
const processedMessages = new Set();

async function processAndSaveToDB(order) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (Math.random() > 0.2) resolve();
      else reject(new Error("DB write failed"));
    }, 100);
  });
}

async function retryProcess(order) {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      await processAndSaveToDB(order);
      return;
    } catch (err) {
      console.log(`Retry ${attempt} failed`);

      if (attempt === MAX_RETRIES) {
        throw err;
      }

      await new Promise(r => setTimeout(r, 500));
    }
  }
}

async function run() {
  await consumer.connect();

  await consumer.subscribe({
    topic: "orders-topic",
    fromBeginning: true,
  });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {

      const order = JSON.parse(message.value.toString());
      const messageId = order.id;

      // Idempotent check
      if (processedMessages.has(messageId)) {
        console.log(`Duplicate skipped: ${messageId}`);
        return;
      }

      try {

        await retryProcess(order);

        processedMessages.add(messageId);

        await consumer.commitOffsets([
          {
            topic,
            partition,
            offset: (parseInt(message.offset) + 1).toString(),
          },
        ]);

        console.log(`Processed order ${messageId}`);

      } catch (error) {
        console.error(`Failed after retries: ${messageId}`);
      }
    },
  });
}

run().catch(console.error);

```

```js
orders-topic
      ↓
consumer
      ↓
process message
   ├── success → commit offset
   ├── fail (retry < max) → send to retry-topic
   └── fail (retry >= max) → send to dlq-topic


orders-topic
orders-retry-topic
orders-dlq-topic


const { kafka } = require('../config');

const consumer = kafka.consumer({
  groupId: "orders-group",
  autoCommit: false,
});

const producer = kafka.producer();

const MAX_RETRIES = 3;

async function processOrder(order) {
  // simulate failure
  if (Math.random() < 0.4) {
    throw new Error("Processing failed");
  }
  console.log("Order processed:", order.orderId);
}

async function run() {
  await consumer.connect();
  await producer.connect();

  await consumer.subscribe({
    topic: "orders-topic",
    fromBeginning: true
  });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {

      const order = JSON.parse(message.value.toString());
      const retryCount = order.retryCount || 0;

      try {
        await processOrder(order);

        await consumer.commitOffsets([
          {
            topic,
            partition,
            offset: (Number(message.offset) + 1).toString(),
          },
        ]);

        console.log(`✅ Success offset=${message.offset}`);

      } catch (error) {

        console.log(`❌ Failed attempt=${retryCount + 1}`);

        if (retryCount < MAX_RETRIES) {

          const retryMessage = {
            ...order,
            retryCount: retryCount + 1,
          };

          await producer.send({
            topic: "orders-retry-topic",
            messages: [
              { value: JSON.stringify(retryMessage) }
            ],
          });

          console.log("🔁 Sent to retry topic");

        } else {

          await producer.send({
            topic: "orders-dlq-topic",
            messages: [
              { value: JSON.stringify(order) }
            ],
          });

          console.log("💀 Sent to DLQ");

        }

        await consumer.commitOffsets([
          {
            topic,
            partition,
            offset: (Number(message.offset) + 1).toString(),
          },
        ]);
      }
    }
  });
}

run().catch(console.error);
---
```
## 5. Advanced Level

---

### 5.1 Exactly-Once Semantics (Transactions)

> **Use Case:** Consume from one topic, process, and produce to another topic atomically. If any step fails, everything rolls back.

#### `advanced/transactions.js`

```js
const { kafka } = require('../config');

const producer = kafka.producer({
  transactionalId: 'my-transactional-producer',
  maxInFlightRequests: 1,
  idempotent: true,
});

const consumer = kafka.consumer({
  groupId: 'transaction-group',
  readUncommitted: false, // Only read committed messages
});

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'raw-orders', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const order = JSON.parse(message.value.toString());
      console.log(`📥 Received raw order: ${order.orderId}`);

      // Create a transaction
      const transaction = await producer.transaction();

      try {
        // Enrich the order
        const enrichedOrder = {
          ...order,
          status: 'VALIDATED',
          tax: (order.amount * 0.18).toFixed(2),
          total: (order.amount * 1.18).toFixed(2),
          processedAt: new Date().toISOString(),
        };

        // Produce to output topic (within transaction)
        await transaction.send({
          topic: 'processed-orders',
          messages: [{ key: order.userId, value: JSON.stringify(enrichedOrder) }],
        });

        // Also send notification (within same transaction)
        await transaction.send({
          topic: 'notifications',
          messages: [
            {
              value: JSON.stringify({
                type: 'ORDER_PROCESSED',
                message: `Order ${order.orderId} processed. Total: $${enrichedOrder.total}`,
              }),
            },
          ],
        });

        // Commit offset within the transaction
        await transaction.sendOffsets({
          consumerGroupId: 'transaction-group',
          topics: [
            {
              topic,
              partitions: [
                { partition, offset: (parseInt(message.offset) + 1).toString() },
              ],
            },
          ],
        });

        // Commit the transaction — all or nothing
        await transaction.commit();
        console.log(`✅ Transaction committed for ${order.orderId}`);
      } catch (error) {
        // Abort — nothing gets written
        await transaction.abort();
        console.error(`❌ Transaction aborted for ${order.orderId}: ${error.message}`);
      }
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

**Key Concepts:**
- `transactionalId` + `idempotent: true` enables exactly-once
- `producer.transaction()` starts an atomic unit of work
- `transaction.commit()` or `transaction.abort()` — all or nothing
- Consumer reads only committed messages with `readUncommitted: false`

---

### 5.2 Dead Letter Queue (DLQ)

> **Use Case:** Messages that fail processing N times get moved to a DLQ topic for later investigation instead of blocking the pipeline.

#### `advanced/dead-letter-queue.js`

```js
const { kafka } = require('../config');

const producer = kafka.producer();
const consumer = kafka.consumer({
  groupId: 'dlq-group',
  autoCommit: false,
});

const MAX_RETRIES = 3;
const DLQ_TOPIC = 'orders-dlq';
const failureCount = new Map(); // Track retry counts per message

function getMessageId(topic, partition, offset) {
  return `${topic}-${partition}-${offset}`;
}

async function processOrder(order) {
  // Simulated processing that can fail
  if (order.amount > 400) {
    throw new Error(`High-value order requires manual review: $${order.amount}`);
  }
  console.log(`✅ Processed order: ${order.orderId} — $${order.amount}`);
}

async function sendToDLQ(originalMessage, error, retries) {
  await producer.send({
    topic: DLQ_TOPIC,
    messages: [
      {
        key: originalMessage.key,
        value: originalMessage.value,
        headers: {
          'original-topic': 'orders-topic',
          'error-message': error.message,
          'retry-count': retries.toString(),
          'failed-at': new Date().toISOString(),
        },
      },
    ],
  });
  console.log(`💀 Sent to DLQ after ${retries} retries`);
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'orders-topic', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const msgId = getMessageId(topic, partition, message.offset);
      const order = JSON.parse(message.value.toString());

      try {
        await processOrder(order);

        // Success — commit offset
        await consumer.commitOffsets([
          { topic, partition, offset: (parseInt(message.offset) + 1).toString() },
        ]);
        failureCount.delete(msgId);
      } catch (error) {
        const retries = (failureCount.get(msgId) || 0) + 1;
        failureCount.set(msgId, retries);

        if (retries >= MAX_RETRIES) {
          // Max retries exceeded — send to DLQ
          await sendToDLQ(message, error, retries);

          // Commit offset to move past the failed message
          await consumer.commitOffsets([
            { topic, partition, offset: (parseInt(message.offset) + 1).toString() },
          ]);
          failureCount.delete(msgId);
        } else {
          console.warn(`⚠️ Retry ${retries}/${MAX_RETRIES} for offset ${message.offset}: ${error.message}`);
        }
      }
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

---

### 5.3 Event Sourcing Pattern

> **Use Case:** Store all state changes as events. Rebuild current state by replaying events.

#### `advanced/event-sourcing.js`

```js
const { kafka } = require('../config');
const { v4: uuidv4 } = require('uuid');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'event-sourcing-group' });

const EVENT_TOPIC = 'account-events';

// In-memory state (in production → database)
const accountState = new Map();

// ─── Event Producer ───

async function emitEvent(aggregateId, eventType, data) {
  const event = {
    eventId: uuidv4(),
    aggregateId,
    eventType,
    data,
    timestamp: new Date().toISOString(),
    version: 1,
  };

  await producer.send({
    topic: EVENT_TOPIC,
    messages: [{ key: aggregateId, value: JSON.stringify(event) }],
  });

  console.log(`📤 Event emitted: ${eventType} for ${aggregateId}`);
  return event;
}

// ─── Event Handlers (Projections) ───

const eventHandlers = {
  ACCOUNT_CREATED: (state, event) => ({
    id: event.aggregateId,
    name: event.data.name,
    balance: 0,
    transactions: [],
    createdAt: event.timestamp,
  }),

  MONEY_DEPOSITED: (state, event) => ({
    ...state,
    balance: state.balance + event.data.amount,
    transactions: [
      ...state.transactions,
      { type: 'DEPOSIT', amount: event.data.amount, at: event.timestamp },
    ],
  }),

  MONEY_WITHDRAWN: (state, event) => {
    if (state.balance < event.data.amount) {
      console.warn(`⚠️ Insufficient funds for withdrawal`);
      return state;
    }
    return {
      ...state,
      balance: state.balance - event.data.amount,
      transactions: [
        ...state.transactions,
        { type: 'WITHDRAWAL', amount: event.data.amount, at: event.timestamp },
      ],
    };
  },
};

// ─── Event Consumer (State Rebuilder) ───

async function startConsumer() {
  await consumer.connect();
  await consumer.subscribe({ topic: EVENT_TOPIC, fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      const handler = eventHandlers[event.eventType];

      if (handler) {
        const currentState = accountState.get(event.aggregateId) || {};
        const newState = handler(currentState, event);
        accountState.set(event.aggregateId, newState);

        console.log(`📊 State updated:`, JSON.stringify(newState, null, 2));
      }
    },
  });
}

// ─── Simulate Banking Operations ───

async function simulateBanking() {
  await producer.connect();

  const accountId = 'ACC-' + uuidv4().slice(0, 8);

  await emitEvent(accountId, 'ACCOUNT_CREATED', { name: 'John Doe' });
  await new Promise((r) => setTimeout(r, 500));

  await emitEvent(accountId, 'MONEY_DEPOSITED', { amount: 1000 });
  await new Promise((r) => setTimeout(r, 500));

  await emitEvent(accountId, 'MONEY_DEPOSITED', { amount: 500 });
  await new Promise((r) => setTimeout(r, 500));

  await emitEvent(accountId, 'MONEY_WITHDRAWN', { amount: 200 });
  await new Promise((r) => setTimeout(r, 500));

  await emitEvent(accountId, 'MONEY_WITHDRAWN', { amount: 2000 }); // Will fail — insufficient funds
  await new Promise((r) => setTimeout(r, 1000));

  // Print final state
  console.log('\n🏦 FINAL ACCOUNT STATE:');
  console.log(JSON.stringify(accountState.get(accountId), null, 2));
}

async function run() {
  await startConsumer();
  await new Promise((r) => setTimeout(r, 2000)); // Wait for consumer to be ready
  await simulateBanking();
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

---

### 5.4 Stream Processing (Real-time Aggregation)

> **Use Case:** Real-time analytics — aggregate IoT sensor data in tumbling time windows.

#### `advanced/stream-processing.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({ groupId: 'stream-processing-group' });
const producer = kafka.producer();

// Tumbling window aggregation
const WINDOW_SIZE_MS = 10000; // 10-second windows
const windows = new Map();

function getWindowKey(deviceId, timestamp) {
  const windowStart = Math.floor(timestamp / WINDOW_SIZE_MS) * WINDOW_SIZE_MS;
  return `${deviceId}:${windowStart}`;
}

function aggregate(windowKey, reading) {
  if (!windows.has(windowKey)) {
    windows.set(windowKey, {
      deviceId: reading.deviceId,
      count: 0,
      sumTemp: 0,
      sumHumidity: 0,
      minTemp: Infinity,
      maxTemp: -Infinity,
      windowStart: null,
    });
  }

  const agg = windows.get(windowKey);
  const temp = parseFloat(reading.temperature);
  const humidity = parseFloat(reading.humidity);

  agg.count += 1;
  agg.sumTemp += temp;
  agg.sumHumidity += humidity;
  agg.minTemp = Math.min(agg.minTemp, temp);
  agg.maxTemp = Math.max(agg.maxTemp, temp);
  agg.windowStart = agg.windowStart || reading.timestamp;
}

// Emit completed windows every WINDOW_SIZE_MS
setInterval(async () => {
  const now = Date.now();
  for (const [key, agg] of windows.entries()) {
    const windowEnd = parseInt(key.split(':')[1]) + WINDOW_SIZE_MS;
    if (now > windowEnd) {
      const result = {
        deviceId: agg.deviceId,
        avgTemperature: (agg.sumTemp / agg.count).toFixed(2),
        avgHumidity: (agg.sumHumidity / agg.count).toFixed(2),
        minTemperature: agg.minTemp.toFixed(2),
        maxTemperature: agg.maxTemp.toFixed(2),
        messageCount: agg.count,
        windowStart: new Date(parseInt(key.split(':')[1])).toISOString(),
        windowEnd: new Date(windowEnd).toISOString(),
      };

      // Emit aggregated result
      await producer.send({
        topic: 'sensor-aggregated',
        messages: [{ key: agg.deviceId, value: JSON.stringify(result) }],
      });

      console.log(`📊 Window result:`, result);
      windows.delete(key);
    }
  }
}, 5000);

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'iot-sensor-data', fromBeginning: false });

  console.log('🔄 Stream processor started (10s tumbling windows)');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const reading = JSON.parse(message.value.toString());
      const windowKey = getWindowKey(reading.deviceId, reading.timestamp || Date.now());
      aggregate(windowKey, reading);
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

---

### 5.5 Schema Registry (Avro Serialization)

> **Use Case:** Enforce message schema contracts between producers and consumers. Schema evolves safely.

#### `advanced/schema-registry.js`

```js
const { kafka } = require('../config');
const { SchemaRegistry, SchemaType } = require('@kafkajs/confluent-schema-registry');

// Connect to Schema Registry (needs Confluent Schema Registry running on port 8081)
const registry = new SchemaRegistry({ host: 'http://localhost:8081' });

// Define Avro Schema
const orderSchema = {
  type: 'record',
  name: 'Order',
  namespace: 'com.example.orders',
  fields: [
    { name: 'orderId', type: 'string' },
    { name: 'userId', type: 'string' },
    { name: 'amount', type: 'double' },
    { name: 'currency', type: { type: 'enum', name: 'Currency', symbols: ['USD', 'EUR', 'GBP'] } },
    { name: 'createdAt', type: 'string' },
  ],
};

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'schema-registry-group' });

async function run() {
  // Register schema
  const { id: schemaId } = await registry.register({
    type: SchemaType.AVRO,
    schema: JSON.stringify(orderSchema),
  });
  console.log(`📝 Schema registered with ID: ${schemaId}`);

  // ─── PRODUCE with Avro ───
  await producer.connect();

  const order = {
    orderId: 'ORD-5001',
    userId: 'user-101',
    amount: 299.99,
    currency: 'USD',
    createdAt: new Date().toISOString(),
  };

  // Encode using schema registry
  const encodedValue = await registry.encode(schemaId, order);

  await producer.send({
    topic: 'avro-orders',
    messages: [{ key: order.userId, value: encodedValue }],
  });
  console.log('📤 Avro-encoded order sent');

  // ─── CONSUME with Avro ───
  await consumer.connect();
  await consumer.subscribe({ topic: 'avro-orders', fromBeginning: true });

  await consumer.run({
    eachMessage: async ({ message }) => {
      // Decode automatically using schema registry
      const decodedOrder = await registry.decode(message.value);
      console.log('📥 Decoded order:', decodedOrder);
    },
  });
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

> **Note:** Schema Registry requires Confluent Platform. Add it to docker-compose (see Section 6).

---

### 5.6 Admin Client — Topic Management

> **Use Case:** Programmatically create, list, and delete topics.

#### `advanced/admin-client.js`

```js
const { kafka } = require('../config');

const admin = kafka.admin();

async function run() {
  await admin.connect();
  console.log('✅ Admin client connected\n');

  // ─── Create Topics ───
  const topicsToCreate = [
    { topic: 'orders-topic', numPartitions: 3, replicationFactor: 1 },
    { topic: 'notifications', numPartitions: 2, replicationFactor: 1 },
    { topic: 'orders-dlq', numPartitions: 1, replicationFactor: 1 },
    { topic: 'iot-sensor-data', numPartitions: 6, replicationFactor: 1 },
    { topic: 'raw-orders', numPartitions: 3, replicationFactor: 1 },
    { topic: 'processed-orders', numPartitions: 3, replicationFactor: 1 },
    { topic: 'account-events', numPartitions: 3, replicationFactor: 1 },
    { topic: 'sensor-aggregated', numPartitions: 3, replicationFactor: 1 },
    { topic: 'basic-topic', numPartitions: 3, replicationFactor: 1 },
  ];

  const created = await admin.createTopics({ topics: topicsToCreate });
  console.log('📝 Topics created:', created ? 'Yes (new)' : 'Already exist');

  // ─── List Topics ───
  const topics = await admin.listTopics();
  console.log('\n📋 All topics:');
  topics.filter(t => !t.startsWith('__')).forEach(t => console.log(`   • ${t}`));

  // ─── Topic Metadata ───
  const metadata = await admin.fetchTopicMetadata({ topics: ['orders-topic'] });
  console.log('\n📊 orders-topic metadata:');
  metadata.topics[0].partitions.forEach((p) => {
    console.log(`   Partition ${p.partitionId}: leader=${p.leader}, replicas=${p.replicas}, isr=${p.isr}`);
  });

  // ─── Consumer Group Offsets ───
  const groups = await admin.listGroups();
  console.log('\n👥 Consumer groups:');
  groups.groups.forEach((g) => console.log(`   • ${g.groupId} (${g.protocolType})`));

  // ─── Delete a Topic (careful!) ───
  // await admin.deleteTopics({ topics: ['test-delete-me'] });

  await admin.disconnect();
}

run().catch(console.error);
```

**Run this first to create all the topics needed for the other examples:**
```bash
node advanced/admin-client.js
```

---

### 5.7 Real-time Notification System (Express + Kafka + SSE)

> **Use Case:** Web server that produces events to Kafka and pushes real-time updates to browser clients via Server-Sent Events.

#### `advanced/realtime-server.js`

```js
const express = require('express');
const { kafka } = require('../config');

const app = express();
app.use(express.json());

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'realtime-notification-group' });

// Store SSE clients
const sseClients = new Set();

// ─── SSE Endpoint — Browser connects here ───
app.get('/events', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });

  sseClients.add(res);
  console.log(`🔗 SSE client connected (total: ${sseClients.size})`);

  req.on('close', () => {
    sseClients.delete(res);
    console.log(`🔌 SSE client disconnected (total: ${sseClients.size})`);
  });
});

// Broadcast to all SSE clients
function broadcast(event, data) {
  const message = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  sseClients.forEach((client) => client.write(message));
}

// ─── REST API — Produce events ───
app.post('/api/orders', async (req, res) => {
  const order = {
    orderId: `ORD-${Date.now()}`,
    ...req.body,
    createdAt: new Date().toISOString(),
  };

  await producer.send({
    topic: 'orders-topic',
    messages: [{ key: order.userId || 'anonymous', value: JSON.stringify(order) }],
  });

  res.json({ success: true, order });
});

app.post('/api/notifications', async (req, res) => {
  const notification = {
    id: `NOTIF-${Date.now()}`,
    ...req.body,
    createdAt: new Date().toISOString(),
  };

  await producer.send({
    topic: 'notifications',
    messages: [{ value: JSON.stringify(notification) }],
  });

  res.json({ success: true, notification });
});

// ─── Serve a simple HTML page ───
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head><title>Kafka Real-time Dashboard</title></head>
    <body>
      <h1>📡 Kafka Real-time Dashboard</h1>
      <div id="events" style="font-family:monospace; background:#111; color:#0f0; padding:20px; height:400px; overflow-y:scroll;"></div>
      <script>
        const events = new EventSource('/events');
        const div = document.getElementById('events');

        events.addEventListener('order', (e) => {
          const data = JSON.parse(e.data);
          div.innerHTML += '<p>🛒 ORDER: ' + data.orderId + ' — $' + data.amount + '</p>';
          div.scrollTop = div.scrollHeight;
        });

        events.addEventListener('notification', (e) => {
          const data = JSON.parse(e.data);
          div.innerHTML += '<p>🔔 NOTIF: [' + data.type + '] ' + data.message + '</p>';
          div.scrollTop = div.scrollHeight;
        });
      </script>
    </body>
    </html>
  `);
});

// ─── Kafka Consumer → SSE Broadcast ───
async function startKafkaConsumer() {
  await consumer.connect();
  await consumer.subscribe({ topics: ['orders-topic', 'notifications'], fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const data = JSON.parse(message.value.toString());

      if (topic === 'orders-topic') {
        broadcast('order', data);
      } else if (topic === 'notifications') {
        broadcast('notification', data);
      }
    },
  });
}

// ─── Start Everything ───
async function start() {
  await producer.connect();
  await startKafkaConsumer();

  app.listen(3000, () => {
    console.log('🚀 Server running at http://localhost:3000');
    console.log('📡 SSE endpoint: http://localhost:3000/events');
    console.log('\nTest with:');
    console.log('  curl -X POST http://localhost:3000/api/orders -H "Content-Type: application/json" -d \'{"userId":"user-1","amount":99.99}\'');
    console.log('  curl -X POST http://localhost:3000/api/notifications -H "Content-Type: application/json" -d \'{"type":"INFO","message":"Hello World!"}\'');
  });
}

start().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node advanced/realtime-server.js
# Open http://localhost:3000 in browser
# Then send events via curl:
curl -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId":"user-1","amount":99.99}'
```

---

## 6. Docker Setup — Complete Containerized Environment

---

### 6.1 Dockerfile (Node.js App)

> Containerize the Kafka Node.js application for production deployment.

#### `Dockerfile`

```dockerfile
# ─────────────────────────────────────────────
# Stage 1: Install dependencies
# ─────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy package files first (Docker layer caching)
COPY package.json package-lock.json* ./

# Install production dependencies only
RUN npm ci --only=production

# ─────────────────────────────────────────────
# Stage 2: Production image
# ─────────────────────────────────────────────
FROM node:20-alpine AS runner

WORKDIR /app

# Add non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

# Copy dependencies from stage 1
COPY --from=deps /app/node_modules ./node_modules

# Copy application source code
COPY config.js ./
COPY basic/ ./basic/
COPY intermediate/ ./intermediate/
COPY advanced/ ./advanced/
COPY package.json ./

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

USER appuser

# Expose port for the realtime server (Section 5.7)
EXPOSE 3000

# Health check (for realtime-server)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/ || exit 1

# Default: run the realtime server (override with docker run command)
CMD ["node", "advanced/realtime-server.js"]
```

**Key Points:**
- **Multi-stage build** — keeps final image small (~180MB vs ~900MB)
- **Non-root user** — security best practice
- **Layer caching** — `package.json` copied first so `npm ci` only reruns when dependencies change
- **Health check** — Docker monitors if the app is alive
- **Override CMD** — run any example by overriding the command

---

### 6.2 `.dockerignore`

> Prevent unnecessary files from being copied into the Docker image.

#### `.dockerignore`

```
node_modules
npm-debug.log*
.git
.gitignore
.env
.env.*
docker-compose.yml
Dockerfile
*.md
.DS_Store
.vscode
coverage
.nyc_output
```

---

### 6.3 Dockerfile for Development (with hot-reload)

> Use this during development — mounts source code and auto-restarts on changes.

#### `Dockerfile.dev`

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Install nodemon globally for hot-reload
RUN npm install -g nodemon

COPY package.json package-lock.json* ./
RUN npm install

# Source code is mounted via docker-compose volume (not copied)

EXPOSE 3000

# Default: run realtime-server with nodemon (auto-restart on file changes)
CMD ["nodemon", "--watch", ".", "--ext", "js,json", "advanced/realtime-server.js"]
```

---

### 6.4 Docker Compose — Full Stack (Kafka + App)

> Complete `docker-compose.yml` with Kafka cluster **AND** the Node.js app containerized.

#### `docker-compose.yml`

```yaml
version: '3.8'

# ─── Shared network ───
networks:
  kafka-net:
    driver: bridge

# ─── Persistent volumes ───
volumes:
  zookeeper-data:
  kafka-1-data:
  kafka-2-data:

services:

  # ═══════════════════════════════════════════
  # INFRASTRUCTURE
  # ═══════════════════════════════════════════

  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper
    hostname: zookeeper
    networks:
      - kafka-net
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_SYNC_LIMIT: 2
    volumes:
      - zookeeper-data:/var/lib/zookeeper/data
    healthcheck:
      test: ["CMD", "echo", "ruok", "|", "nc", "localhost", "2181"]
      interval: 10s
      timeout: 5s
      retries: 5

  kafka-1:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-1
    hostname: kafka-1
    networks:
      - kafka-net
    depends_on:
      zookeeper:
        condition: service_healthy
    ports:
      - "9092:9092"
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka-1:29092,EXTERNAL://localhost:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 2
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_DELETE_TOPIC_ENABLE: "true"
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_LOG_RETENTION_HOURS: 168
      KAFKA_LOG_RETENTION_BYTES: 1073741824
    volumes:
      - kafka-1-data:/var/lib/kafka/data
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9092"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s

  kafka-2:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-2
    hostname: kafka-2
    networks:
      - kafka-net
    depends_on:
      zookeeper:
        condition: service_healthy
    ports:
      - "9093:9093"
      - "29093:29093"
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:29093,EXTERNAL://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka-2:29093,EXTERNAL://localhost:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 2
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_DELETE_TOPIC_ENABLE: "true"
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_NUM_PARTITIONS: 3
    volumes:
      - kafka-2-data:/var/lib/kafka/data
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9093"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s

  # ═══════════════════════════════════════════
  # SCHEMA REGISTRY (for Avro example 5.5)
  # ═══════════════════════════════════════════

  schema-registry:
    image: confluentinc/cp-schema-registry:7.5.0
    container_name: schema-registry
    hostname: schema-registry
    networks:
      - kafka-net
    depends_on:
      kafka-1:
        condition: service_healthy
    ports:
      - "8081:8081"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: kafka-1:29092
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
      SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY_LEVEL: BACKWARD
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/subjects"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ═══════════════════════════════════════════
  # TOPIC INIT (auto-create all topics on startup)
  # ═══════════════════════════════════════════

  kafka-init:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-init
    networks:
      - kafka-net
    depends_on:
      kafka-1:
        condition: service_healthy
      kafka-2:
        condition: service_healthy
    entrypoint: ["/bin/bash", "-c"]
    command: |
      "
      echo '⏳ Waiting for Kafka to be fully ready...'
      sleep 5

      echo '📝 Creating topics...'

      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic basic-topic         --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic orders-topic        --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic notifications       --partitions 2 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic orders-dlq          --partitions 1 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic iot-sensor-data     --partitions 6 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic raw-orders          --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic processed-orders    --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic account-events      --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic sensor-aggregated   --partitions 3 --replication-factor 2
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic avro-orders         --partitions 3 --replication-factor 2

      echo ''
      echo '✅ All topics created. Listing:'
      kafka-topics --bootstrap-server kafka-1:29092 --list

      echo ''
      echo '🎉 Kafka initialization complete!'
      "

  # ═══════════════════════════════════════════
  # MONITORING — Kafka UI
  # ═══════════════════════════════════════════

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui
    networks:
      - kafka-net
    depends_on:
      kafka-1:
        condition: service_healthy
      kafka-2:
        condition: service_healthy
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: local-cluster
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-1:29092,kafka-2:29093
      KAFKA_CLUSTERS_0_SCHEMAREGISTRY: http://schema-registry:8081
      KAFKA_CLUSTERS_0_METRICS_PORT: 9997
      DYNAMIC_CONFIG_ENABLED: "true"

  # ═══════════════════════════════════════════
  # NODE.JS APP — Production
  # ═══════════════════════════════════════════

  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: kafka-nodejs-app
    networks:
      - kafka-net
    depends_on:
      kafka-1:
        condition: service_healthy
      kafka-2:
        condition: service_healthy
      kafka-init:
        condition: service_completed_successfully
    ports:
      - "3000:3000"
    environment:
      KAFKA_BROKERS: kafka-1:29092,kafka-2:29093
      SCHEMA_REGISTRY_HOST: http://schema-registry:8081
      NODE_ENV: production
    # Override to run any example:
    # command: ["node", "basic/producer.js"]
    restart: on-failure

  # ═══════════════════════════════════════════
  # NODE.JS APP — Development (with hot-reload)
  # ═══════════════════════════════════════════

  app-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: kafka-nodejs-dev
    networks:
      - kafka-net
    depends_on:
      kafka-1:
        condition: service_healthy
      kafka-2:
        condition: service_healthy
    ports:
      - "3001:3000"
    environment:
      KAFKA_BROKERS: kafka-1:29092,kafka-2:29093
      SCHEMA_REGISTRY_HOST: http://schema-registry:8081
      NODE_ENV: development
    volumes:
      - .:/app                  # Mount source code for hot-reload
      - /app/node_modules       # Exclude node_modules from mount
    profiles:
      - dev                     # Only starts with: docker compose --profile dev up
```

---

### 6.5 Updated `config.js` (Docker-aware)

> Update the shared config to detect whether it's running inside Docker or locally.

#### `config.js` (replace the original)

```js
// config.js
const { Kafka, logLevel } = require('kafkajs');

// Auto-detect environment: Docker uses internal hostnames, local uses localhost
const brokers = process.env.KAFKA_BROKERS
  ? process.env.KAFKA_BROKERS.split(',')
  : ['localhost:9092', 'localhost:9093'];

const kafka = new Kafka({
  clientId: 'kafka-nodejs-lab',
  brokers,
  logLevel: logLevel.WARN,
  retry: {
    initialRetryTime: 300,
    retries: 10,
  },
  // Connection timeout (useful when waiting for Kafka to start)
  connectionTimeout: 10000,
  requestTimeout: 30000,
});

console.log(`🔌 Kafka brokers: ${brokers.join(', ')}`);

module.exports = { kafka };
```

---

### 6.6 Environment File

> Store configuration variables separately.

#### `.env`

```env
# ─── Kafka ───
KAFKA_BROKERS=localhost:9092,localhost:9093
SCHEMA_REGISTRY_HOST=http://localhost:8081

# ─── App ───
NODE_ENV=development
PORT=3000

# ─── Kafka UI ───
KAFKA_UI_PORT=8080
```

---

### 6.7 Docker Commands — Complete Reference

#### Infrastructure Only (for local Node.js development)

```bash
# Start Kafka cluster + UI + auto-create topics
docker compose up -d zookeeper kafka-1 kafka-2 kafka-init kafka-ui schema-registry

# Wait for healthy status
docker compose ps

# Now run Node.js examples locally
node basic/producer.js
node basic/consumer.js
```

#### Full Stack — Production Mode

```bash
# Build and start everything (Kafka + Node.js app)
docker compose up -d --build

# View app logs
docker compose logs -f app

# Open in browser
#   App:      http://localhost:3000
#   Kafka UI: http://localhost:8080
```

#### Full Stack — Development Mode (with hot-reload)

```bash
# Start with dev profile (mounts source code, uses nodemon)
docker compose --profile dev up -d --build

# View dev app logs
docker compose logs -f app-dev

# Edit any .js file → app auto-restarts
# Dev app: http://localhost:3001
```

#### Run Specific Examples in Docker

```bash
# Run basic producer inside container
docker compose run --rm app node basic/producer.js

# Run basic consumer (stays running)
docker compose run --rm app node basic/consumer.js

# Run keyed producer
docker compose run --rm app node intermediate/keyed-producer.js

# Run event sourcing example
docker compose run --rm app node advanced/event-sourcing.js

# Run any example interactively
docker compose run --rm app sh
# Then inside the container:
node basic/producer.js
```

#### Monitoring & Debugging

```bash
# Check all container health statuses
docker compose ps

# View Kafka broker logs
docker compose logs -f kafka-1

# View Zookeeper logs
docker compose logs -f zookeeper

# View app container logs
docker compose logs -f app

# Exec into Kafka container for CLI tools
docker compose exec kafka-1 bash

# List topics from inside Kafka container
docker compose exec kafka-1 kafka-topics --bootstrap-server kafka-1:29092 --list

# Describe a topic
docker compose exec kafka-1 kafka-topics --bootstrap-server kafka-1:29092 --describe --topic orders-topic

# Console consumer (read messages from CLI)
docker compose exec kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:29092 \
  --topic orders-topic \
  --from-beginning

# Console producer (send test messages from CLI)
docker compose exec kafka-1 kafka-console-producer \
  --bootstrap-server kafka-1:29092 \
  --topic basic-topic

# Check consumer group lag
docker compose exec kafka-1 kafka-consumer-groups \
  --bootstrap-server kafka-1:29092 \
  --describe --group basic-group

# Check Schema Registry schemas
curl http://localhost:8081/subjects

# Check Schema Registry versions
curl http://localhost:8081/subjects/avro-orders-value/versions
```

#### Cleanup

```bash
# Stop all containers
docker compose down

# Stop and remove all data (volumes, topics, offsets)
docker compose down -v

# Remove everything including images
docker compose down -v --rmi all

# Prune unused Docker resources
docker system prune -f
```

---

### 6.8 Network Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Docker Network: kafka-net                   │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                   │
│  │Zookeeper │◄───│ Kafka-1  │◄──►│ Kafka-2  │                   │
│  │  :2181   │    │  :29092  │    │  :29093  │                   │
│  └──────────┘    │  :9092*  │    │  :9093*  │                   │
│                  └────┬─────┘    └────┬─────┘                   │
│                       │               │                          │
│              ┌────────┴───────────────┘                          │
│              │                                                   │
│  ┌───────────┴───┐  ┌─────────────┐  ┌─────────────────┐       │
│  │Schema Registry│  │  Kafka UI   │  │  kafka-init     │       │
│  │    :8081*     │  │   :8080*    │  │ (creates topics)│       │
│  └───────────────┘  └─────────────┘  └─────────────────┘       │
│                                                                  │
│  ┌────────────────┐  ┌──────────────────┐                       │
│  │   App (prod)   │  │  App-dev (dev)   │                       │
│  │    :3000*      │  │    :3001*        │                       │
│  │  Dockerfile    │  │  Dockerfile.dev  │                       │
│  └────────────────┘  └──────────────────┘                       │
│                                                                  │
│  * = port exposed to host machine                                │
└─────────────────────────────────────────────────────────────────┘

Host Access:
  http://localhost:3000  → Node.js App (production)
  http://localhost:3001  → Node.js App (development)
  http://localhost:8080  → Kafka UI Dashboard
  http://localhost:8081  → Schema Registry API
  localhost:9092         → Kafka Broker 1 (for local dev)
  localhost:9093         → Kafka Broker 2 (for local dev)
```

---

## 7. Project Structure

```
kafka-nodejs-lab/
├── config.js                              # Shared Kafka client config (Docker-aware)
├── docker-compose.yml                     # Full stack: Kafka + App + Monitoring
├── Dockerfile                             # Production multi-stage build
├── Dockerfile.dev                         # Development with hot-reload
├── .dockerignore                          # Files excluded from Docker build
├── .env                                   # Environment variables
├── package.json
│
├── basic/
│   ├── producer.js                        # 3.1 Simple Producer
│   ├── consumer.js                        # 3.2 Simple Consumer
│   └── consumer-group.js                  # 3.3 Consumer Groups
│
├── intermediate/
│   ├── keyed-producer.js                  # 4.1 Keyed Messages
│   ├── batch-producer.js                  # 4.2 Batch Producing
│   ├── multi-topic-consumer.js            # 4.3 Multiple Topics
│   ├── manual-offset-consumer.js          # 4.4 Manual Offset Management
│   └── resilient-producer.js              # 4.5 Retry & Error Handling
│
└── advanced/
    ├── admin-client.js                    # 5.6 Topic Management (run first!)
    ├── transactions.js                    # 5.1 Exactly-Once Semantics
    ├── dead-letter-queue.js               # 5.2 DLQ Pattern
    ├── event-sourcing.js                  # 5.3 Event Sourcing
    ├── stream-processing.js               # 5.4 Real-time Aggregation
    ├── schema-registry.js                 # 5.5 Avro Serialization
    └── realtime-server.js                 # 5.7 Express + Kafka + SSE
```

---

## 8. Quick Reference & Cheat Sheet

### Execution Order (Recommended)

**Option A: Local Development (Node.js on host)**
```bash
# Step 1: Start Kafka infrastructure only
docker compose up -d zookeeper kafka-1 kafka-2 kafka-init kafka-ui schema-registry

# Step 2: Install dependencies
npm install

# Step 3: Run examples (topics auto-created by kafka-init)
node basic/producer.js
node basic/consumer.js
# ... and so on
```

**Option B: Fully Containerized**
```bash
# Start everything (Kafka + App) in one command
docker compose up -d --build

# Run specific examples
docker compose run --rm app node basic/producer.js

# Open Kafka UI: http://localhost:8080
# Open App:      http://localhost:3000
```

**Option C: Development with Hot-reload**
```bash
# Start with dev profile
docker compose --profile dev up -d --build

# Edit files locally → app-dev auto-restarts
# Dev App: http://localhost:3001
```

### Common KafkaJS Patterns

| Pattern | Code |
|---------|------|
| Create client | `new Kafka({ clientId, brokers })` |
| Create producer | `kafka.producer()` |
| Create consumer | `kafka.consumer({ groupId })` |
| Create admin | `kafka.admin()` |
| Send message | `producer.send({ topic, messages: [{ key, value }] })` |
| Subscribe | `consumer.subscribe({ topic, fromBeginning })` |
| Consume | `consumer.run({ eachMessage: async ({...}) => {} })` |
| Transaction | `const txn = await producer.transaction()` |
| Commit offset | `consumer.commitOffsets([{ topic, partition, offset }])` |

### Key Kafka Concepts

| Concept | Description |
|---------|-------------|
| **Topic** | Named channel/category for messages |
| **Partition** | Ordered, immutable sequence within a topic |
| **Offset** | Position of a message within a partition |
| **Consumer Group** | Set of consumers that cooperatively consume a topic |
| **Key** | Determines which partition a message goes to |
| **Replication** | Copies of partitions across brokers for fault tolerance |
| **ISR** | In-Sync Replicas — replicas that are caught up |
| **Idempotent** | Producer that prevents duplicate messages |
| **Transaction** | Atomic multi-topic produce + offset commit |
| **DLQ** | Dead Letter Queue — where failed messages go |

### Debugging Tips

```bash
# Check if Kafka is running
docker compose ps

# List topics from CLI
docker exec kafka-1 kafka-topics --bootstrap-server localhost:9092 --list

# Consume from CLI (useful for debugging)
docker exec kafka-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic orders-topic --from-beginning

# Check consumer group lag
docker exec kafka-1 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group basic-group

# Open Kafka UI
open http://localhost:8080
```

---

**Happy Streaming! 🎉**
