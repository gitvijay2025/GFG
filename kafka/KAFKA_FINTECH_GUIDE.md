# Apache Kafka for FinTech — Node.js Implementation Guide

> Real-world Kafka patterns for a Financial Technology company: Payments, Fraud Detection, KYC, Ledger, Portfolio Tracking, Notifications & Compliance.

---

## Table of Contents

1. [Overview — Why Kafka for FinTech](#1-overview--why-kafka-for-fintech)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Project Setup](#3-project-setup)
4. [Kafka Topics Map](#4-kafka-topics-map)
5. [Use Case 1 — Payment Processing Pipeline](#5-use-case-1--payment-processing-pipeline)
6. [Use Case 2 — Real-time Fraud Detection](#6-use-case-2--real-time-fraud-detection)
7. [Use Case 3 — KYC (Know Your Customer) Verification](#7-use-case-3--kyc-know-your-customer-verification)
8. [Use Case 4 — Double-Entry Ledger (Event Sourcing)](#8-use-case-4--double-entry-ledger-event-sourcing)
9. [Use Case 5 — Real-time Portfolio & Balance Tracker](#9-use-case-5--real-time-portfolio--balance-tracker)
10. [Use Case 6 — Notification Engine (Email, SMS, Push)](#10-use-case-6--notification-engine-email-sms-push)
11. [Use Case 7 — Regulatory Compliance & Audit Trail](#11-use-case-7--regulatory-compliance--audit-trail)
12. [Use Case 8 — Rate Limiting & Throttling](#12-use-case-8--rate-limiting--throttling)
13. [Use Case 9 — Merchant Settlement (Batch + CRON)](#13-use-case-9--merchant-settlement-batch--cron)
14. [Use Case 10 — Real-time Dashboard (Express + SSE + Kafka)](#14-use-case-10--real-time-dashboard-express--sse--kafka)
15. [Docker Compose — Full FinTech Stack](#15-docker-compose--full-fintech-stack)
16. [Project Structure](#16-project-structure)
17. [How to Run — Step by Step](#17-how-to-run--step-by-step)

---

## 1. Overview — Why Kafka for FinTech

| Challenge | How Kafka Solves It |
|-----------|-------------------|
| **High throughput** — millions of transactions/day | Kafka handles 100K+ msgs/sec per partition |
| **Exactly-once payments** — no double-charge | Kafka transactions + idempotent producers |
| **Real-time fraud detection** — sub-second decisions | Stream processing on payment events |
| **Audit trail** — regulators need full history | Kafka retains events immutably (log-based) |
| **Microservice decoupling** — payment ↔ fraud ↔ KYC ↔ ledger | Topics act as contracts between services |
| **Event sourcing** — rebuild account state from events | Replay from any offset at any time |
| **Ordering guarantees** — per-user transaction ordering | Key-based partitioning by `userId` or `accountId` |
| **Dead Letter Queue** — don't lose failed transactions | Failed messages route to DLQ for manual review |

---

## 2. Architecture Diagram

```
                        ┌─────────────────────────────────────────────────────┐
                        │                  KAFKA CLUSTER                       │
                        │                                                      │
  ┌──────────┐          │  ┌──────────────────┐  ┌───────────────────┐        │
  │  Mobile   │──POST──▶│  │ payment.initiated │  │ payment.completed │        │
  │   App     │         │  └────────┬─────────┘  └───────────────────┘        │
  └──────────┘          │           │                                          │
                        │           ▼                                          │
  ┌──────────┐          │  ┌──────────────────┐  ┌───────────────────┐        │
  │   Web    │──POST──▶│  │ fraud.check       │  │ fraud.alerts      │        │
  │  Portal   │         │  └──────────────────┘  └───────────────────┘        │
  └──────────┘          │                                                      │
                        │  ┌──────────────────┐  ┌───────────────────┐        │
  ┌──────────┐          │  │ kyc.verification  │  │ kyc.completed     │        │
  │ Partner   │──API──▶│  └──────────────────┘  └───────────────────┘        │
  │   API     │         │                                                      │
  └──────────┘          │  ┌──────────────────┐  ┌───────────────────┐        │
                        │  │ ledger.entries    │  │ notifications     │        │
                        │  └──────────────────┘  └───────────────────┘        │
                        │                                                      │
                        │  ┌──────────────────┐  ┌───────────────────┐        │
                        │  │ audit.trail       │  │ payment.dlq       │        │
                        │  └──────────────────┘  └───────────────────┘        │
                        └─────────────────────────────────────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────────┐
              ▼                      ▼                          ▼
     ┌────────────────┐   ┌──────────────────┐      ┌──────────────────┐
     │ Fraud Detection │   │  Ledger Service  │      │  Notification    │
     │    Service      │   │ (Event Sourcing) │      │    Service       │
     └────────────────┘   └──────────────────┘      └──────────────────┘
              │                      │                          │
              ▼                      ▼                          ▼
     ┌────────────────┐   ┌──────────────────┐      ┌──────────────────┐
     │   Risk DB      │   │   PostgreSQL     │      │  Email/SMS/Push  │
     └────────────────┘   └──────────────────┘      └──────────────────┘
```

---

## 3. Project Setup

```bash
mkdir fintech-kafka && cd fintech-kafka

npm init -y

npm install kafkajs express uuid dotenv crypto-js
```

### `config.js` — Shared Kafka Config

```js
// config.js
const { Kafka, logLevel } = require('kafkajs');

const brokers = process.env.KAFKA_BROKERS
  ? process.env.KAFKA_BROKERS.split(',')
  : ['localhost:9092', 'localhost:9093'];

const kafka = new Kafka({
  clientId: 'fintech-platform',
  brokers,
  logLevel: logLevel.WARN,
  retry: { initialRetryTime: 300, retries: 10 },
  connectionTimeout: 10000,
  requestTimeout: 30000,
});

module.exports = { kafka };
```

### `helpers.js` — Shared Utilities

```js
// helpers.js
const { v4: uuidv4 } = require('uuid');

function generateId(prefix) {
  return `${prefix}-${uuidv4().slice(0, 12)}`;
}

function timestamp() {
  return new Date().toISOString();
}

function money(amount) {
  return parseFloat(amount.toFixed(2));
}

// Graceful shutdown helper
function gracefulShutdown(...clients) {
  process.on('SIGINT', async () => {
    console.log('\n🛑 Shutting down gracefully...');
    for (const client of clients) {
      await client.disconnect();
    }
    process.exit(0);
  });
}

module.exports = { generateId, timestamp, money, gracefulShutdown };
```

---

## 4. Kafka Topics Map

> Run `node setup/create-topics.js` first to create all topics.

### `setup/create-topics.js`

```js
const { kafka } = require('../config');

const admin = kafka.admin();

const TOPICS = [
  // ─── Payment Pipeline ───
  { topic: 'payment.initiated',    numPartitions: 6, replicationFactor: 1 },
  { topic: 'payment.validated',    numPartitions: 6, replicationFactor: 1 },
  { topic: 'payment.completed',    numPartitions: 6, replicationFactor: 1 },
  { topic: 'payment.failed',       numPartitions: 3, replicationFactor: 1 },
  { topic: 'payment.dlq',          numPartitions: 1, replicationFactor: 1 },

  // ─── Fraud ───
  { topic: 'fraud.check',          numPartitions: 6, replicationFactor: 1 },
  { topic: 'fraud.alerts',         numPartitions: 3, replicationFactor: 1 },

  // ─── KYC ───
  { topic: 'kyc.verification',     numPartitions: 3, replicationFactor: 1 },
  { topic: 'kyc.completed',        numPartitions: 3, replicationFactor: 1 },

  // ─── Ledger ───
  { topic: 'ledger.entries',       numPartitions: 6, replicationFactor: 1 },

  // ─── Notifications ───
  { topic: 'notifications',        numPartitions: 3, replicationFactor: 1 },

  // ─── Audit & Compliance ───
  { topic: 'audit.trail',          numPartitions: 3, replicationFactor: 1 },

  // ─── Portfolio ───
  { topic: 'portfolio.updates',    numPartitions: 6, replicationFactor: 1 },

  // ─── Settlements ───
  { topic: 'settlement.batch',     numPartitions: 3, replicationFactor: 1 },
  { topic: 'settlement.completed', numPartitions: 3, replicationFactor: 1 },
];

async function run() {
  await admin.connect();
  console.log('✅ Admin connected\n');

  const created = await admin.createTopics({ topics: TOPICS });
  console.log(created ? '📝 Topics created!' : '📝 Topics already exist.');

  const list = await admin.listTopics();
  console.log('\n📋 All topics:');
  list.filter(t => !t.startsWith('__')).sort().forEach(t => console.log(`   • ${t}`));

  await admin.disconnect();
}

run().catch(console.error);
```

**Run:**
```bash
node setup/create-topics.js
```

| Topic | Partitions | Purpose |
|-------|-----------|---------|
| `payment.initiated` | 6 | Incoming payment requests |
| `payment.validated` | 6 | Payments that passed fraud + KYC checks |
| `payment.completed` | 6 | Successfully processed payments |
| `payment.failed` | 3 | Payments that failed |
| `payment.dlq` | 1 | Dead letter queue for unprocessable payments |
| `fraud.check` | 6 | Payments pending fraud analysis |
| `fraud.alerts` | 3 | High-risk transactions flagged |
| `kyc.verification` | 3 | Users pending KYC verification |
| `kyc.completed` | 3 | KYC results (approved/rejected) |
| `ledger.entries` | 6 | Double-entry bookkeeping events |
| `notifications` | 3 | Email/SMS/Push notifications |
| `audit.trail` | 3 | All actions for regulatory compliance |
| `portfolio.updates` | 6 | Balance/portfolio changes |
| `settlement.batch` | 3 | End-of-day merchant settlements |
| `settlement.completed` | 3 | Completed settlement records |

---

## 5. Use Case 1 — Payment Processing Pipeline

> **Scenario:** User initiates a payment → Fraud Check → KYC Validation → Ledger Entry → Notification. Each step is a separate Kafka consumer (microservice).

### Flow

```
User → [payment.initiated] → Fraud Service → [payment.validated] → Payment Processor
           │                                        │
           ▼                                        ▼
     [fraud.check]                          [ledger.entries]
     [fraud.alerts]                         [payment.completed]
                                            [notifications]
                                            [audit.trail]
```

### `payments/initiate-payment.js` — Payment Producer

```js
const { kafka } = require('../config');
const { generateId, timestamp, money } = require('../helpers');

const producer = kafka.producer({ idempotent: true });

async function initiatePayment(paymentData) {
  const payment = {
    paymentId: generateId('PAY'),
    senderId: paymentData.senderId,
    receiverId: paymentData.receiverId,
    amount: money(paymentData.amount),
    currency: paymentData.currency || 'USD',
    type: paymentData.type || 'P2P',           // P2P, MERCHANT, WITHDRAWAL, DEPOSIT
    method: paymentData.method || 'WALLET',     // WALLET, BANK, CARD, UPI
    description: paymentData.description || '',
    status: 'INITIATED',
    initiatedAt: timestamp(),
    metadata: {
      ipAddress: paymentData.ipAddress || '0.0.0.0',
      deviceId: paymentData.deviceId || 'unknown',
      userAgent: paymentData.userAgent || 'unknown',
      location: paymentData.location || null,
    },
  };

  await producer.send({
    topic: 'payment.initiated',
    messages: [{
      key: payment.senderId,   // All payments from same user → same partition → ordered
      value: JSON.stringify(payment),
      headers: {
        'event-type': 'PAYMENT_INITIATED',
        'correlation-id': payment.paymentId,
      },
    }],
  });

  console.log(`💳 Payment initiated: ${payment.paymentId} | ${payment.senderId} → ${payment.receiverId} | $${payment.amount}`);
  return payment;
}

// ─── Simulate multiple payments ───
async function run() {
  await producer.connect();

  const payments = [
    { senderId: 'USER-001', receiverId: 'USER-002', amount: 50.00, type: 'P2P', method: 'WALLET', ipAddress: '192.168.1.10' },
    { senderId: 'USER-001', receiverId: 'MERCHANT-100', amount: 299.99, type: 'MERCHANT', method: 'CARD', ipAddress: '192.168.1.10' },
    { senderId: 'USER-003', receiverId: 'USER-004', amount: 15000, type: 'P2P', method: 'BANK', ipAddress: '10.0.0.5' },       // High-value → fraud alert
    { senderId: 'USER-005', receiverId: 'MERCHANT-200', amount: 19.99, type: 'MERCHANT', method: 'UPI', ipAddress: '203.0.113.1' },
    { senderId: 'USER-001', receiverId: 'USER-006', amount: 5000, type: 'P2P', method: 'WALLET', ipAddress: '198.51.100.1', location: 'Nigeria' }, // Suspicious location
    { senderId: 'USER-007', receiverId: 'USER-008', amount: 0.01, type: 'P2P', method: 'WALLET' },
    { senderId: 'USER-002', receiverId: 'MERCHANT-300', amount: 1250.00, type: 'MERCHANT', method: 'CARD', ipAddress: '192.168.1.20' },
  ];

  for (const p of payments) {
    await initiatePayment(p);
    await new Promise(r => setTimeout(r, 300));
  }

  console.log(`\n✅ ${payments.length} payments initiated`);
  await producer.disconnect();
}

run().catch(console.error);
```

### `payments/payment-processor.js` — Core Payment Service

```js
const { kafka } = require('../config');
const { timestamp } = require('../helpers');

const producer = kafka.producer({ idempotent: true });
const consumer = kafka.consumer({ groupId: 'payment-processor-group', autoCommit: false });

// Simulated account balances (in production → database)
const balances = new Map([
  ['USER-001', 10000],
  ['USER-002', 5000],
  ['USER-003', 25000],
  ['USER-004', 100],
  ['USER-005', 8000],
  ['USER-006', 500],
  ['USER-007', 1],
  ['USER-008', 0],
]);

async function processPayment(payment) {
  const senderBalance = balances.get(payment.senderId) || 0;

  if (senderBalance < payment.amount) {
    return { success: false, reason: 'INSUFFICIENT_FUNDS', balance: senderBalance };
  }

  // Debit sender, Credit receiver
  balances.set(payment.senderId, senderBalance - payment.amount);
  balances.set(payment.receiverId, (balances.get(payment.receiverId) || 0) + payment.amount);

  return {
    success: true,
    senderNewBalance: balances.get(payment.senderId),
    receiverNewBalance: balances.get(payment.receiverId),
  };
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'payment.validated', fromBeginning: true });

  console.log('🏦 Payment Processor running...\n');

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      const payment = JSON.parse(message.value.toString());
      console.log(`📥 Processing: ${payment.paymentId} | $${payment.amount}`);

      const result = await processPayment(payment);

      if (result.success) {
        // ─── Payment Completed ───
        const completed = {
          ...payment,
          status: 'COMPLETED',
          completedAt: timestamp(),
          senderNewBalance: result.senderNewBalance,
          receiverNewBalance: result.receiverNewBalance,
        };

        await producer.send({
          topic: 'payment.completed',
          messages: [{ key: payment.senderId, value: JSON.stringify(completed) }],
        });

        // ─── Ledger Entry (double-entry) ───
        await producer.send({
          topic: 'ledger.entries',
          messages: [
            {
              key: payment.senderId,
              value: JSON.stringify({
                entryType: 'DEBIT',
                accountId: payment.senderId,
                amount: payment.amount,
                currency: payment.currency,
                paymentId: payment.paymentId,
                balance: result.senderNewBalance,
                timestamp: timestamp(),
              }),
            },
            {
              key: payment.receiverId,
              value: JSON.stringify({
                entryType: 'CREDIT',
                accountId: payment.receiverId,
                amount: payment.amount,
                currency: payment.currency,
                paymentId: payment.paymentId,
                balance: result.receiverNewBalance,
                timestamp: timestamp(),
              }),
            },
          ],
        });

        // ─── Notifications ───
        await producer.send({
          topic: 'notifications',
          messages: [
            {
              value: JSON.stringify({
                userId: payment.senderId,
                type: 'PAYMENT_SENT',
                channel: 'push',
                title: 'Payment Sent',
                body: `You sent $${payment.amount} to ${payment.receiverId}. New balance: $${result.senderNewBalance}`,
                paymentId: payment.paymentId,
                timestamp: timestamp(),
              }),
            },
            {
              value: JSON.stringify({
                userId: payment.receiverId,
                type: 'PAYMENT_RECEIVED',
                channel: 'push',
                title: 'Payment Received',
                body: `You received $${payment.amount} from ${payment.senderId}. New balance: $${result.receiverNewBalance}`,
                paymentId: payment.paymentId,
                timestamp: timestamp(),
              }),
            },
          ],
        });

        // ─── Audit Trail ───
        await producer.send({
          topic: 'audit.trail',
          messages: [{
            key: payment.paymentId,
            value: JSON.stringify({
              action: 'PAYMENT_COMPLETED',
              paymentId: payment.paymentId,
              senderId: payment.senderId,
              receiverId: payment.receiverId,
              amount: payment.amount,
              timestamp: timestamp(),
            }),
          }],
        });

        console.log(`✅ COMPLETED: ${payment.paymentId} | Sender balance: $${result.senderNewBalance}`);
      } else {
        // ─── Payment Failed ───
        const failed = {
          ...payment,
          status: 'FAILED',
          failedAt: timestamp(),
          reason: result.reason,
        };

        await producer.send({
          topic: 'payment.failed',
          messages: [{ key: payment.senderId, value: JSON.stringify(failed) }],
        });

        await producer.send({
          topic: 'notifications',
          messages: [{
            value: JSON.stringify({
              userId: payment.senderId,
              type: 'PAYMENT_FAILED',
              channel: 'push',
              title: 'Payment Failed',
              body: `Payment of $${payment.amount} failed: ${result.reason}. Balance: $${result.balance}`,
              paymentId: payment.paymentId,
              timestamp: timestamp(),
            }),
          }],
        });

        console.log(`❌ FAILED: ${payment.paymentId} | Reason: ${result.reason}`);
      }

      await consumer.commitOffsets([{ topic, partition, offset: (parseInt(message.offset) + 1).toString() }]);
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

**Run:**
```bash
# Terminal 1 — Start the payment processor
node payments/payment-processor.js

# Terminal 2 — Start the fraud detector (see Use Case 2)
node fraud/fraud-detector.js

# Terminal 3 — Initiate payments
node payments/initiate-payment.js
```

---

## 6. Use Case 2 — Real-time Fraud Detection

> **Scenario:** Every initiated payment is analyzed in real-time. Rules check for: high amounts, velocity (too many txns), suspicious locations, new accounts. Risky payments are flagged; clean ones proceed.

### `fraud/fraud-detector.js`

```js
const { kafka } = require('../config');
const { timestamp } = require('../helpers');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'fraud-detection-group' });

// ─── In-memory state (production → Redis / time-series DB) ───
const userTxHistory = new Map();     // userId → [{ amount, time }]
const flaggedUsers = new Set();       // Blacklisted user IDs

// ─── Fraud Rules ───

const RULES = {
  // Rule 1: Transaction amount exceeds threshold
  highAmount: (payment) => {
    if (payment.amount > 10000) {
      return { triggered: true, rule: 'HIGH_AMOUNT', risk: 'HIGH', reason: `Amount $${payment.amount} exceeds $10,000 threshold` };
    }
    return { triggered: false };
  },

  // Rule 2: Velocity check — more than 5 transactions in 1 minute
  velocity: (payment) => {
    const history = userTxHistory.get(payment.senderId) || [];
    const oneMinuteAgo = Date.now() - 60000;
    const recentTxns = history.filter(h => h.time > oneMinuteAgo);

    if (recentTxns.length >= 5) {
      return { triggered: true, rule: 'VELOCITY', risk: 'HIGH', reason: `${recentTxns.length} transactions in last 60s` };
    }
    return { triggered: false };
  },

  // Rule 3: Suspicious location
  suspiciousLocation: (payment) => {
    const suspiciousLocations = ['Nigeria', 'Unknown', 'VPN-Detected'];
    if (payment.metadata?.location && suspiciousLocations.includes(payment.metadata.location)) {
      return { triggered: true, rule: 'SUSPICIOUS_LOCATION', risk: 'MEDIUM', reason: `Location: ${payment.metadata.location}` };
    }
    return { triggered: false };
  },

  // Rule 4: Flagged user
  blacklisted: (payment) => {
    if (flaggedUsers.has(payment.senderId) || flaggedUsers.has(payment.receiverId)) {
      return { triggered: true, rule: 'BLACKLISTED_USER', risk: 'CRITICAL', reason: 'User is on the flagged list' };
    }
    return { triggered: false };
  },

  // Rule 5: Micro-transaction pattern (money laundering indicator)
  microTransaction: (payment) => {
    if (payment.amount < 1.00 && payment.type === 'P2P') {
      const history = userTxHistory.get(payment.senderId) || [];
      const microTxns = history.filter(h => h.amount < 1.00 && h.time > Date.now() - 3600000);
      if (microTxns.length >= 3) {
        return { triggered: true, rule: 'MICRO_TXN_PATTERN', risk: 'MEDIUM', reason: `${microTxns.length} micro-transactions in last hour` };
      }
    }
    return { triggered: false };
  },
};

function analyzePayment(payment) {
  const alerts = [];
  let overallRisk = 'LOW';
  const riskPriority = { LOW: 0, MEDIUM: 1, HIGH: 2, CRITICAL: 3 };

  for (const [ruleName, ruleFunc] of Object.entries(RULES)) {
    const result = ruleFunc(payment);
    if (result.triggered) {
      alerts.push(result);
      if (riskPriority[result.risk] > riskPriority[overallRisk]) {
        overallRisk = result.risk;
      }
    }
  }

  return { alerts, overallRisk, passed: overallRisk === 'LOW' || overallRisk === 'MEDIUM' };
}

function updateHistory(payment) {
  const history = userTxHistory.get(payment.senderId) || [];
  history.push({ amount: payment.amount, time: Date.now() });
  // Keep only last 100 entries per user
  if (history.length > 100) history.shift();
  userTxHistory.set(payment.senderId, history);
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'payment.initiated', fromBeginning: true });

  console.log('🔍 Fraud Detection Service running...\n');
  console.log('Rules active: HIGH_AMOUNT, VELOCITY, SUSPICIOUS_LOCATION, BLACKLISTED, MICRO_TXN_PATTERN\n');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());
      console.log(`🔎 Analyzing: ${payment.paymentId} | $${payment.amount} | ${payment.senderId}`);

      const { alerts, overallRisk, passed } = analyzePayment(payment);
      updateHistory(payment);

      if (passed) {
        // ✅ Payment is clean → forward to validation
        await producer.send({
          topic: 'payment.validated',
          messages: [{
            key: payment.senderId,
            value: JSON.stringify({
              ...payment,
              status: 'VALIDATED',
              fraudCheck: { risk: overallRisk, alerts, checkedAt: timestamp() },
            }),
          }],
        });
        console.log(`  ✅ PASSED (risk: ${overallRisk}) → payment.validated`);
      } else {
        // 🚨 Payment is suspicious → flag it
        await producer.send({
          topic: 'fraud.alerts',
          messages: [{
            key: payment.senderId,
            value: JSON.stringify({
              paymentId: payment.paymentId,
              senderId: payment.senderId,
              receiverId: payment.receiverId,
              amount: payment.amount,
              risk: overallRisk,
              alerts,
              flaggedAt: timestamp(),
              payment,
            }),
          }],
        });

        // Also send to payment.failed
        await producer.send({
          topic: 'payment.failed',
          messages: [{
            key: payment.senderId,
            value: JSON.stringify({
              ...payment,
              status: 'BLOCKED_BY_FRAUD',
              reason: alerts.map(a => a.reason).join('; '),
              failedAt: timestamp(),
            }),
          }],
        });

        // Notify the user
        await producer.send({
          topic: 'notifications',
          messages: [{
            value: JSON.stringify({
              userId: payment.senderId,
              type: 'FRAUD_BLOCK',
              channel: 'email',
              title: 'Payment Blocked — Security Alert',
              body: `Your payment of $${payment.amount} was blocked for security review. Reference: ${payment.paymentId}`,
              timestamp: timestamp(),
            }),
          }],
        });

        // Audit trail
        await producer.send({
          topic: 'audit.trail',
          messages: [{
            key: payment.paymentId,
            value: JSON.stringify({
              action: 'FRAUD_BLOCKED',
              paymentId: payment.paymentId,
              risk: overallRisk,
              alerts,
              timestamp: timestamp(),
            }),
          }],
        });

        console.log(`  🚨 BLOCKED (risk: ${overallRisk}) → fraud.alerts`);
        alerts.forEach(a => console.log(`     ⚠️ ${a.rule}: ${a.reason}`));
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

**Run:**
```bash
node fraud/fraud-detector.js
```

---

## 7. Use Case 3 — KYC (Know Your Customer) Verification

> **Scenario:** When a user registers or hits a transaction limit, a KYC check is triggered. Verification runs asynchronously and results come back through Kafka.

### `kyc/kyc-service.js`

```js
const { kafka } = require('../config');
const { generateId, timestamp } = require('../helpers');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'kyc-verification-group' });

// Simulated KYC database
const kycDatabase = new Map();

// Simulated verification (in production → call third-party API like Jumio, Onfido)
async function verifyIdentity(request) {
  await new Promise(r => setTimeout(r, 500 + Math.random() * 1500)); // Simulate API latency

  // Simulate outcomes
  const random = Math.random();
  if (random < 0.7) {
    return { status: 'APPROVED', level: 'FULL', message: 'Identity verified successfully' };
  } else if (random < 0.9) {
    return { status: 'PENDING_REVIEW', level: 'BASIC', message: 'Manual review required — document unclear' };
  } else {
    return { status: 'REJECTED', level: 'NONE', message: 'Identity verification failed — document mismatch' };
  }
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'kyc.verification', fromBeginning: true });

  console.log('🆔 KYC Verification Service running...\n');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const request = JSON.parse(message.value.toString());
      console.log(`📥 KYC request for: ${request.userId} | Type: ${request.verificationType}`);

      const result = await verifyIdentity(request);
      const kycResult = {
        kycId: generateId('KYC'),
        userId: request.userId,
        verificationType: request.verificationType,
        documents: request.documents,
        result: result.status,
        kycLevel: result.level,
        message: result.message,
        requestedAt: request.requestedAt,
        completedAt: timestamp(),
      };

      // Store result
      kycDatabase.set(request.userId, kycResult);

      // Publish result
      await producer.send({
        topic: 'kyc.completed',
        messages: [{ key: request.userId, value: JSON.stringify(kycResult) }],
      });

      // Notify user
      const notifBody = result.status === 'APPROVED'
        ? '✅ Your identity has been verified! You now have full access.'
        : result.status === 'PENDING_REVIEW'
          ? '⏳ Your documents are under review. We\'ll update you within 24 hours.'
          : '❌ Verification failed. Please re-submit your documents.';

      await producer.send({
        topic: 'notifications',
        messages: [{
          value: JSON.stringify({
            userId: request.userId,
            type: 'KYC_UPDATE',
            channel: 'email',
            title: `KYC Verification: ${result.status}`,
            body: notifBody,
            timestamp: timestamp(),
          }),
        }],
      });

      // Audit
      await producer.send({
        topic: 'audit.trail',
        messages: [{
          key: request.userId,
          value: JSON.stringify({
            action: 'KYC_COMPLETED',
            userId: request.userId,
            result: result.status,
            kycLevel: result.level,
            timestamp: timestamp(),
          }),
        }],
      });

      const icon = result.status === 'APPROVED' ? '✅' : result.status === 'PENDING_REVIEW' ? '⏳' : '❌';
      console.log(`  ${icon} ${result.status}: ${request.userId} → Level: ${result.level}`);
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

### `kyc/submit-kyc.js` — KYC Request Producer

```js
const { kafka } = require('../config');
const { timestamp } = require('../helpers');

const producer = kafka.producer();

async function run() {
  await producer.connect();

  const kycRequests = [
    { userId: 'USER-001', verificationType: 'ID_DOCUMENT', documents: ['passport.jpg', 'selfie.jpg'] },
    { userId: 'USER-003', verificationType: 'ADDRESS_PROOF', documents: ['utility_bill.pdf'] },
    { userId: 'USER-005', verificationType: 'FULL_KYC', documents: ['drivers_license.jpg', 'selfie.jpg', 'bank_statement.pdf'] },
  ];

  for (const req of kycRequests) {
    await producer.send({
      topic: 'kyc.verification',
      messages: [{
        key: req.userId,
        value: JSON.stringify({ ...req, requestedAt: timestamp() }),
      }],
    });
    console.log(`📤 KYC submitted for ${req.userId} (${req.verificationType})`);
  }

  await producer.disconnect();
}

run().catch(console.error);
```

**Run:**
```bash
# Terminal 1
node kyc/kyc-service.js

# Terminal 2
node kyc/submit-kyc.js
```

---

## 8. Use Case 4 — Double-Entry Ledger (Event Sourcing)

> **Scenario:** Every financial transaction creates two ledger entries (DEBIT + CREDIT). The ledger is the source of truth. Account balances are projections rebuilt from ledger events.

### `ledger/ledger-service.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({ groupId: 'ledger-service-group' });

// In-memory ledger (production → append-only database table)
const ledger = [];
const accountBalances = new Map();

async function run() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'ledger.entries', fromBeginning: true });

  console.log('📒 Ledger Service running...\n');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const entry = JSON.parse(message.value.toString());

      // Append to ledger (immutable)
      ledger.push(entry);

      // Update running balance projection
      const currentBalance = accountBalances.get(entry.accountId) || 0;
      const newBalance = entry.entryType === 'CREDIT'
        ? currentBalance + entry.amount
        : currentBalance - entry.amount;

      accountBalances.set(entry.accountId, parseFloat(newBalance.toFixed(2)));

      const icon = entry.entryType === 'CREDIT' ? '💚' : '🔴';
      console.log(`${icon} ${entry.entryType}: ${entry.accountId} | $${entry.amount} | Balance: $${accountBalances.get(entry.accountId)} | Ref: ${entry.paymentId}`);
    },
  });

  // Print summary every 10 seconds
  setInterval(() => {
    if (ledger.length > 0) {
      console.log('\n📊 ─── Account Balances Summary ───');
      for (const [account, balance] of accountBalances.entries()) {
        console.log(`   ${account}: $${balance.toFixed(2)}`);
      }
      console.log(`   Total entries: ${ledger.length}`);
      console.log('───────────────────────────────────\n');
    }
  }, 10000);
}

run().catch(console.error);

process.on('SIGINT', async () => {
  console.log('\n📒 Final Ledger:');
  ledger.forEach((e, i) => {
    console.log(`  ${i + 1}. ${e.entryType} ${e.accountId} $${e.amount} (${e.paymentId})`);
  });
  await consumer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node ledger/ledger-service.js
```

---

## 9. Use Case 5 — Real-time Portfolio & Balance Tracker

> **Scenario:** Aggregate all completed payments per user in real-time to maintain up-to-date balance and transaction history.

### `portfolio/portfolio-tracker.js`

```js
const { kafka } = require('../config');
const { timestamp } = require('../helpers');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'portfolio-tracker-group' });

// In-memory portfolios (production → Redis + PostgreSQL)
const portfolios = new Map();

function getOrCreatePortfolio(userId) {
  if (!portfolios.has(userId)) {
    portfolios.set(userId, {
      userId,
      balance: 0,
      totalSent: 0,
      totalReceived: 0,
      transactionCount: 0,
      lastActivity: null,
      recentTransactions: [],
    });
  }
  return portfolios.get(userId);
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'payment.completed', fromBeginning: true });

  console.log('📈 Portfolio Tracker running...\n');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());

      // Update sender portfolio
      const senderPortfolio = getOrCreatePortfolio(payment.senderId);
      senderPortfolio.balance = payment.senderNewBalance;
      senderPortfolio.totalSent += payment.amount;
      senderPortfolio.transactionCount += 1;
      senderPortfolio.lastActivity = timestamp();
      senderPortfolio.recentTransactions.unshift({
        type: 'SENT',
        to: payment.receiverId,
        amount: payment.amount,
        paymentId: payment.paymentId,
        time: payment.completedAt,
      });
      if (senderPortfolio.recentTransactions.length > 20) senderPortfolio.recentTransactions.pop();

      // Update receiver portfolio
      const receiverPortfolio = getOrCreatePortfolio(payment.receiverId);
      receiverPortfolio.balance = payment.receiverNewBalance;
      receiverPortfolio.totalReceived += payment.amount;
      receiverPortfolio.transactionCount += 1;
      receiverPortfolio.lastActivity = timestamp();
      receiverPortfolio.recentTransactions.unshift({
        type: 'RECEIVED',
        from: payment.senderId,
        amount: payment.amount,
        paymentId: payment.paymentId,
        time: payment.completedAt,
      });
      if (receiverPortfolio.recentTransactions.length > 20) receiverPortfolio.recentTransactions.pop();

      // Publish portfolio updates
      await producer.send({
        topic: 'portfolio.updates',
        messages: [
          { key: payment.senderId, value: JSON.stringify(senderPortfolio) },
          { key: payment.receiverId, value: JSON.stringify(receiverPortfolio) },
        ],
      });

      console.log(`📊 Portfolio updated: ${payment.senderId} ($${senderPortfolio.balance}) | ${payment.receiverId} ($${receiverPortfolio.balance})`);
    },
  });

  // Print all portfolios every 15 seconds
  setInterval(() => {
    if (portfolios.size > 0) {
      console.log('\n═══════ PORTFOLIO SUMMARY ═══════');
      for (const [userId, p] of portfolios.entries()) {
        console.log(`  ${userId}: Balance=$${p.balance.toFixed(2)} | Sent=$${p.totalSent.toFixed(2)} | Received=$${p.totalReceived.toFixed(2)} | Txns=${p.transactionCount}`);
      }
      console.log('═════════════════════════════════\n');
    }
  }, 15000);
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node portfolio/portfolio-tracker.js
```

---

## 10. Use Case 6 — Notification Engine (Email, SMS, Push)

> **Scenario:** Centralized notification service that routes messages to the right channel (email, SMS, push) based on type.

### `notifications/notification-service.js`

```js
const { kafka } = require('../config');

const consumer = kafka.consumer({ groupId: 'notification-engine-group' });

// Simulated delivery channels
async function sendEmail(userId, title, body) {
  await new Promise(r => setTimeout(r, 100));
  console.log(`  📧 EMAIL → ${userId}: "${title}" — ${body}`);
}

async function sendSMS(userId, title, body) {
  await new Promise(r => setTimeout(r, 50));
  console.log(`  📱 SMS → ${userId}: "${title}"`);
}

async function sendPush(userId, title, body) {
  await new Promise(r => setTimeout(r, 30));
  console.log(`  🔔 PUSH → ${userId}: "${title}"`);
}

// Channel routing
const channelHandlers = {
  email: sendEmail,
  sms: sendSMS,
  push: sendPush,
};

// Notification type → default channel mapping
const typeChannelMap = {
  PAYMENT_SENT: 'push',
  PAYMENT_RECEIVED: 'push',
  PAYMENT_FAILED: 'push',
  FRAUD_BLOCK: 'email',
  KYC_UPDATE: 'email',
  SETTLEMENT_COMPLETE: 'email',
  SECURITY_ALERT: 'sms',
};

async function run() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'notifications', fromBeginning: true });

  console.log('🔔 Notification Engine running...\n');

  let totalSent = 0;

  await consumer.run({
    eachMessage: async ({ message }) => {
      const notif = JSON.parse(message.value.toString());

      // Determine channel: explicit or mapped from type
      const channel = notif.channel || typeChannelMap[notif.type] || 'push';
      const handler = channelHandlers[channel];

      if (handler) {
        await handler(notif.userId, notif.title, notif.body);
        totalSent++;
      } else {
        console.log(`  ⚠️ Unknown channel: ${channel}`);
      }
    },
  });

  // Stats every 10 seconds
  setInterval(() => {
    if (totalSent > 0) {
      console.log(`\n📊 Notifications sent: ${totalSent}\n`);
    }
  }, 10000);
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node notifications/notification-service.js
```

---

## 11. Use Case 7 — Regulatory Compliance & Audit Trail

> **Scenario:** All financial events are captured in an immutable audit log for regulatory reporting (PCI-DSS, SOX, AML compliance).

### `compliance/audit-service.js`

```js
const { kafka } = require('../config');
const fs = require('fs');
const path = require('path');

const consumer = kafka.consumer({ groupId: 'audit-compliance-group' });

// Write to append-only audit log file (production → immutable DB like Amazon QLDB, or write-once storage)
const AUDIT_LOG_FILE = path.join(__dirname, '..', 'audit.log');
const auditBuffer = [];

function writeAuditEntry(entry) {
  const logLine = JSON.stringify({
    ...entry,
    _auditMeta: {
      ingestedAt: new Date().toISOString(),
      source: 'kafka-audit-consumer',
      version: '1.0',
    },
  });

  auditBuffer.push(logLine);

  // Flush to file every 10 entries (batch write for performance)
  if (auditBuffer.length >= 10) {
    fs.appendFileSync(AUDIT_LOG_FILE, auditBuffer.join('\n') + '\n');
    auditBuffer.length = 0;
  }
}

async function run() {
  await consumer.connect();
  await consumer.subscribe({ topic: 'audit.trail', fromBeginning: true });

  console.log('🏛️ Audit & Compliance Service running...');
  console.log(`📁 Writing to: ${AUDIT_LOG_FILE}\n`);

  let entryCount = 0;

  await consumer.run({
    eachMessage: async ({ message }) => {
      const event = JSON.parse(message.value.toString());
      writeAuditEntry(event);
      entryCount++;

      console.log(`📝 Audit #${entryCount}: [${event.action}] ${event.paymentId || event.userId || 'N/A'}`);
    },
  });

  // Flush remaining entries on shutdown
  process.on('SIGINT', async () => {
    if (auditBuffer.length > 0) {
      fs.appendFileSync(AUDIT_LOG_FILE, auditBuffer.join('\n') + '\n');
      console.log(`\n💾 Flushed ${auditBuffer.length} remaining audit entries`);
    }
    console.log(`\n🏛️ Total audit entries written: ${entryCount}`);
    await consumer.disconnect();
    process.exit(0);
  });
}

run().catch(console.error);
```

**Run:**
```bash
node compliance/audit-service.js

# View the audit log
cat audit.log | jq .
```

---

## 12. Use Case 8 — Rate Limiting & Throttling

> **Scenario:** Prevent users from exceeding transaction limits (daily limit, per-minute limit) before processing.

### `ratelimit/rate-limiter.js`

```js
const { kafka } = require('../config');
const { timestamp } = require('../helpers');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'rate-limiter-group' });

// Rate limit config per user tier
const LIMITS = {
  BASIC:   { perMinute: 3,  dailyAmount: 1000 },
  PREMIUM: { perMinute: 10, dailyAmount: 50000 },
  BUSINESS:{ perMinute: 50, dailyAmount: 500000 },
};

// User tier mapping (production → database)
const userTiers = new Map([
  ['USER-001', 'PREMIUM'],
  ['USER-002', 'BASIC'],
  ['USER-003', 'PREMIUM'],
  ['USER-005', 'BASIC'],
  ['USER-007', 'BASIC'],
]);

// Sliding window counters
const minuteWindows = new Map();  // userId → [{ amount, time }]
const dailyTotals = new Map();    // userId → { amount, date }

function checkRateLimit(payment) {
  const userId = payment.senderId;
  const tier = userTiers.get(userId) || 'BASIC';
  const limits = LIMITS[tier];
  const now = Date.now();

  // Per-minute check
  const minuteHistory = minuteWindows.get(userId) || [];
  const recentMinute = minuteHistory.filter(h => h.time > now - 60000);
  minuteWindows.set(userId, recentMinute);

  if (recentMinute.length >= limits.perMinute) {
    return {
      allowed: false,
      reason: `Rate limit exceeded: ${recentMinute.length}/${limits.perMinute} transactions per minute (${tier} tier)`,
    };
  }

  // Daily amount check
  const today = new Date().toISOString().split('T')[0];
  const daily = dailyTotals.get(userId) || { amount: 0, date: today };
  if (daily.date !== today) {
    daily.amount = 0;
    daily.date = today;
  }

  if (daily.amount + payment.amount > limits.dailyAmount) {
    return {
      allowed: false,
      reason: `Daily limit exceeded: $${daily.amount + payment.amount} / $${limits.dailyAmount} (${tier} tier)`,
    };
  }

  // Update counters
  recentMinute.push({ amount: payment.amount, time: now });
  minuteWindows.set(userId, recentMinute);
  daily.amount += payment.amount;
  dailyTotals.set(userId, daily);

  return { allowed: true };
}

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'payment.initiated', fromBeginning: true });

  console.log('⏱️ Rate Limiter running...\n');
  console.log('Tier Limits:');
  Object.entries(LIMITS).forEach(([tier, l]) => {
    console.log(`  ${tier}: ${l.perMinute}/min, $${l.dailyAmount}/day`);
  });
  console.log();

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());
      const result = checkRateLimit(payment);

      if (result.allowed) {
        // Forward to fraud check (next step in pipeline)
        await producer.send({
          topic: 'fraud.check',
          messages: [{
            key: payment.senderId,
            value: JSON.stringify({ ...payment, rateLimitPassed: true }),
          }],
        });
        console.log(`  ✅ ${payment.paymentId} — Rate limit OK`);
      } else {
        await producer.send({
          topic: 'payment.failed',
          messages: [{
            key: payment.senderId,
            value: JSON.stringify({
              ...payment,
              status: 'RATE_LIMITED',
              reason: result.reason,
              failedAt: timestamp(),
            }),
          }],
        });
        console.log(`  🚫 ${payment.paymentId} — ${result.reason}`);
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

**Run:**
```bash
node ratelimit/rate-limiter.js
```

---

## 13. Use Case 9 — Merchant Settlement (Batch + CRON)

> **Scenario:** At end-of-day, aggregate all merchant payments and produce settlement records for payout.

### `settlement/settlement-service.js`

```js
const { kafka } = require('../config');
const { generateId, timestamp, money } = require('../helpers');

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'settlement-service-group' });

// Accumulate merchant payments throughout the day
const merchantAccumulator = new Map();  // merchantId → { total, count, payments[] }

async function run() {
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: 'payment.completed', fromBeginning: true });

  console.log('💰 Settlement Service running...\n');

  await consumer.run({
    eachMessage: async ({ message }) => {
      const payment = JSON.parse(message.value.toString());

      // Only accumulate MERCHANT type payments
      if (payment.type !== 'MERCHANT') return;

      const merchantId = payment.receiverId;
      const acc = merchantAccumulator.get(merchantId) || { total: 0, count: 0, fees: 0, payments: [] };

      const fee = money(payment.amount * 0.029 + 0.30);  // 2.9% + $0.30 processing fee
      const net = money(payment.amount - fee);

      acc.total += net;
      acc.fees += fee;
      acc.count += 1;
      acc.payments.push({
        paymentId: payment.paymentId,
        amount: payment.amount,
        fee,
        net,
        from: payment.senderId,
        time: payment.completedAt,
      });

      merchantAccumulator.set(merchantId, acc);
      console.log(`  📥 Accumulated: ${merchantId} +$${net} (fee: $${fee}) | Total: $${money(acc.total)} from ${acc.count} txns`);
    },
  });

  // ─── Settlement CRON — runs every 30 seconds (demo) / daily in production ───
  setInterval(async () => {
    if (merchantAccumulator.size === 0) return;

    console.log('\n═══════════════════════════════════');
    console.log('💰 RUNNING SETTLEMENT BATCH...');
    console.log('═══════════════════════════════════\n');

    for (const [merchantId, acc] of merchantAccumulator.entries()) {
      const settlement = {
        settlementId: generateId('SET'),
        merchantId,
        totalGross: money(acc.payments.reduce((sum, p) => sum + p.amount, 0)),
        totalFees: money(acc.fees),
        totalNet: money(acc.total),
        transactionCount: acc.count,
        payments: acc.payments,
        settledAt: timestamp(),
        status: 'SETTLED',
      };

      await producer.send({
        topic: 'settlement.completed',
        messages: [{ key: merchantId, value: JSON.stringify(settlement) }],
      });

      // Notify merchant
      await producer.send({
        topic: 'notifications',
        messages: [{
          value: JSON.stringify({
            userId: merchantId,
            type: 'SETTLEMENT_COMPLETE',
            channel: 'email',
            title: 'Daily Settlement Complete',
            body: `${settlement.settlementId}: ${acc.count} transactions, Gross: $${settlement.totalGross}, Fees: $${settlement.totalFees}, Net payout: $${settlement.totalNet}`,
            timestamp: timestamp(),
          }),
        }],
      });

      console.log(`  ✅ ${settlement.settlementId} | ${merchantId}: ${acc.count} txns | Gross: $${settlement.totalGross} | Fees: $${settlement.totalFees} | Net: $${settlement.totalNet}`);
    }

    merchantAccumulator.clear();
    console.log('\n💰 Settlement batch complete.\n');
  }, 30000); // Every 30 seconds for demo; use node-cron for production
}

run().catch(console.error);

process.on('SIGINT', async () => {
  await consumer.disconnect();
  await producer.disconnect();
  process.exit(0);
});
```

**Run:**
```bash
node settlement/settlement-service.js
```

---

## 14. Use Case 10 — Real-time Dashboard (Express + SSE + Kafka)

> **Scenario:** Live web dashboard showing payment activity, fraud alerts, and system metrics in real-time.

### `dashboard/server.js`

```js
const express = require('express');
const { kafka } = require('../config');

const app = express();
app.use(express.json());

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'dashboard-consumer-group' });

const sseClients = new Set();
const stats = {
  totalPayments: 0,
  totalAmount: 0,
  completedPayments: 0,
  failedPayments: 0,
  fraudBlocked: 0,
  recentEvents: [],
};

// ─── SSE Endpoint ───
app.get('/events', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });
  sseClients.add(res);
  // Send current stats immediately
  res.write(`event: stats\ndata: ${JSON.stringify(stats)}\n\n`);
  req.on('close', () => sseClients.delete(res));
});

function broadcast(event, data) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  sseClients.forEach(c => c.write(msg));
}

// ─── API to initiate a payment from dashboard ───
app.post('/api/payment', async (req, res) => {
  const payment = {
    paymentId: `PAY-${Date.now()}`,
    senderId: req.body.senderId,
    receiverId: req.body.receiverId,
    amount: parseFloat(req.body.amount),
    currency: 'USD',
    type: req.body.type || 'P2P',
    method: 'WALLET',
    status: 'INITIATED',
    initiatedAt: new Date().toISOString(),
    metadata: { ipAddress: req.ip, deviceId: 'dashboard' },
  };

  await producer.send({
    topic: 'payment.initiated',
    messages: [{ key: payment.senderId, value: JSON.stringify(payment) }],
  });

  res.json({ success: true, payment });
});

app.get('/api/stats', (req, res) => res.json(stats));

// ─── Dashboard HTML ───
app.get('/', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>FinTech Kafka Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Segoe UI', sans-serif; background: #0a0e27; color: #e0e0e0; padding: 20px; }
    h1 { color: #00d4ff; margin-bottom: 20px; }
    .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 20px; }
    .card { background: #1a1f3a; border-radius: 10px; padding: 20px; text-align: center; border: 1px solid #2a2f5a; }
    .card .number { font-size: 2em; font-weight: bold; color: #00d4ff; }
    .card .label { color: #888; font-size: 0.9em; margin-top: 5px; }
    .card.danger .number { color: #ff4757; }
    .card.success .number { color: #2ed573; }
    .card.warning .number { color: #ffa502; }
    .events { background: #0d1117; border: 1px solid #2a2f5a; border-radius: 10px; padding: 15px; height: 400px; overflow-y: auto; font-family: 'Courier New', monospace; font-size: 13px; }
    .events p { padding: 4px 0; border-bottom: 1px solid #1a1f3a; }
    .form-row { display: flex; gap: 10px; margin-bottom: 20px; }
    input, button { padding: 10px 15px; border-radius: 6px; border: 1px solid #2a2f5a; background: #1a1f3a; color: #e0e0e0; font-size: 14px; }
    button { background: #00d4ff; color: #000; cursor: pointer; font-weight: bold; border: none; }
    button:hover { background: #00b8d4; }
    h2 { color: #888; margin-bottom: 10px; font-size: 1em; text-transform: uppercase; letter-spacing: 2px; }
  </style>
</head>
<body>
  <h1>🏦 FinTech Kafka — Live Dashboard</h1>

  <div class="grid">
    <div class="card"><div class="number" id="total">0</div><div class="label">Total Payments</div></div>
    <div class="card success"><div class="number" id="completed">0</div><div class="label">Completed</div></div>
    <div class="card danger"><div class="number" id="failed">0</div><div class="label">Failed</div></div>
    <div class="card warning"><div class="number" id="fraud">0</div><div class="label">Fraud Blocked</div></div>
  </div>

  <h2>Quick Payment</h2>
  <div class="form-row">
    <input id="sender" placeholder="Sender (e.g. USER-001)" value="USER-001">
    <input id="receiver" placeholder="Receiver (e.g. USER-002)" value="USER-002">
    <input id="amount" placeholder="Amount" type="number" value="100">
    <button onclick="sendPayment()">Send Payment</button>
  </div>

  <h2>Live Event Stream</h2>
  <div class="events" id="events"></div>

  <script>
    const evtSource = new EventSource('/events');
    const eventsDiv = document.getElementById('events');

    function addEvent(icon, text, color) {
      const p = document.createElement('p');
      p.style.color = color || '#e0e0e0';
      p.textContent = icon + ' ' + new Date().toLocaleTimeString() + ' — ' + text;
      eventsDiv.prepend(p);
      if (eventsDiv.children.length > 100) eventsDiv.lastChild.remove();
    }

    evtSource.addEventListener('stats', (e) => {
      const s = JSON.parse(e.data);
      document.getElementById('total').textContent = s.totalPayments;
      document.getElementById('completed').textContent = s.completedPayments;
      document.getElementById('failed').textContent = s.failedPayments;
      document.getElementById('fraud').textContent = s.fraudBlocked;
    });

    evtSource.addEventListener('payment_initiated', (e) => {
      const d = JSON.parse(e.data);
      addEvent('💳', 'Payment initiated: ' + d.paymentId + ' $' + d.amount, '#00d4ff');
    });

    evtSource.addEventListener('payment_completed', (e) => {
      const d = JSON.parse(e.data);
      addEvent('✅', 'Completed: ' + d.paymentId + ' $' + d.amount + ' (' + d.senderId + ' → ' + d.receiverId + ')', '#2ed573');
    });

    evtSource.addEventListener('payment_failed', (e) => {
      const d = JSON.parse(e.data);
      addEvent('❌', 'Failed: ' + d.paymentId + ' — ' + d.reason, '#ff4757');
    });

    evtSource.addEventListener('fraud_alert', (e) => {
      const d = JSON.parse(e.data);
      addEvent('🚨', 'FRAUD: ' + d.paymentId + ' $' + d.amount + ' Risk: ' + d.risk, '#ffa502');
    });

    async function sendPayment() {
      const res = await fetch('/api/payment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          senderId: document.getElementById('sender').value,
          receiverId: document.getElementById('receiver').value,
          amount: document.getElementById('amount').value,
        }),
      });
      const data = await res.json();
      addEvent('📤', 'Sent: ' + data.payment.paymentId, '#888');
    }
  </script>
</body>
</html>`);
});

// ─── Kafka Consumer → SSE ───
async function startConsumer() {
  await consumer.connect();
  await consumer.subscribe({
    topics: ['payment.initiated', 'payment.completed', 'payment.failed', 'fraud.alerts'],
    fromBeginning: false,
  });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const data = JSON.parse(message.value.toString());

      switch (topic) {
        case 'payment.initiated':
          stats.totalPayments++;
          stats.totalAmount += data.amount || 0;
          broadcast('payment_initiated', data);
          broadcast('stats', stats);
          break;

        case 'payment.completed':
          stats.completedPayments++;
          broadcast('payment_completed', data);
          broadcast('stats', stats);
          break;

        case 'payment.failed':
          stats.failedPayments++;
          broadcast('payment_failed', data);
          broadcast('stats', stats);
          break;

        case 'fraud.alerts':
          stats.fraudBlocked++;
          broadcast('fraud_alert', data);
          broadcast('stats', stats);
          break;
      }
    },
  });
}

// ─── Start ───
async function start() {
  await producer.connect();
  await startConsumer();
  app.listen(3000, () => {
    console.log('🚀 FinTech Dashboard: http://localhost:3000');
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
node dashboard/server.js
# Open http://localhost:3000
```

---

## 15. Docker Compose — Full FinTech Stack

### `docker-compose.yml`

```yaml
version: '3.8'

networks:
  fintech-net:
    driver: bridge

volumes:
  zookeeper-data:
  kafka-1-data:
  kafka-2-data:

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper
    networks: [fintech-net]
    ports: ["2181:2181"]
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    volumes: [zookeeper-data:/var/lib/zookeeper/data]
    healthcheck:
      test: ["CMD", "echo", "ruok", "|", "nc", "localhost", "2181"]
      interval: 10s
      timeout: 5s
      retries: 5

  kafka-1:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-1
    networks: [fintech-net]
    depends_on:
      zookeeper: { condition: service_healthy }
    ports: ["9092:9092"]
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:29092,EXTERNAL://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka-1:29092,EXTERNAL://localhost:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_NUM_PARTITIONS: 6
    volumes: [kafka-1-data:/var/lib/kafka/data]
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9092"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s

  kafka-2:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-2
    networks: [fintech-net]
    depends_on:
      zookeeper: { condition: service_healthy }
    ports: ["9093:9093"]
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:29093,EXTERNAL://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka-2:29093,EXTERNAL://localhost:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_NUM_PARTITIONS: 6
    volumes: [kafka-2-data:/var/lib/kafka/data]
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions", "--bootstrap-server", "localhost:9093"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s

  kafka-init:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka-init
    networks: [fintech-net]
    depends_on:
      kafka-1: { condition: service_healthy }
      kafka-2: { condition: service_healthy }
    entrypoint: ["/bin/bash", "-c"]
    command: |
      "
      echo '⏳ Creating FinTech topics...'
      sleep 5
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic payment.initiated    --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic payment.validated    --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic payment.completed    --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic payment.failed       --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic payment.dlq          --partitions 1 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic fraud.check          --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic fraud.alerts         --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic kyc.verification     --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic kyc.completed        --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic ledger.entries       --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic notifications        --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic audit.trail          --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic portfolio.updates    --partitions 6 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic settlement.batch     --partitions 3 --replication-factor 1
      kafka-topics --bootstrap-server kafka-1:29092 --create --if-not-exists --topic settlement.completed --partitions 3 --replication-factor 1

      echo '✅ All FinTech topics created!'
      kafka-topics --bootstrap-server kafka-1:29092 --list
      "

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: kafka-ui
    networks: [fintech-net]
    depends_on:
      kafka-1: { condition: service_healthy }
    ports: ["8080:8080"]
    environment:
      KAFKA_CLUSTERS_0_NAME: fintech-cluster
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka-1:29092,kafka-2:29093
      DYNAMIC_CONFIG_ENABLED: "true"
```

**Start:**
```bash
docker compose up -d
# Wait for all services to be healthy
docker compose ps
# Open Kafka UI: http://localhost:8080
```

---

## 16. Project Structure

```
fintech-kafka/
├── config.js                       # Shared Kafka client config
├── helpers.js                      # Utility functions
├── docker-compose.yml              # Kafka cluster + UI
├── package.json
│
├── setup/
│   └── create-topics.js            # Create all FinTech topics
│
├── payments/
│   ├── initiate-payment.js         # 💳 Payment producer (Use Case 1)
│   └── payment-processor.js        # 🏦 Core payment service (Use Case 1)
│
├── fraud/
│   └── fraud-detector.js           # 🔍 Real-time fraud detection (Use Case 2)
│
├── kyc/
│   ├── submit-kyc.js               # 📤 KYC request producer (Use Case 3)
│   └── kyc-service.js              # 🆔 KYC verification service (Use Case 3)
│
├── ledger/
│   └── ledger-service.js           # 📒 Double-entry ledger (Use Case 4)
│
├── portfolio/
│   └── portfolio-tracker.js        # 📈 Real-time balance tracker (Use Case 5)
│
├── notifications/
│   └── notification-service.js     # 🔔 Email/SMS/Push engine (Use Case 6)
│
├── compliance/
│   └── audit-service.js            # 🏛️ Audit trail logger (Use Case 7)
│
├── ratelimit/
│   └── rate-limiter.js             # ⏱️ Rate limiting (Use Case 8)
│
├── settlement/
│   └── settlement-service.js       # 💰 Merchant settlement (Use Case 9)
│
└── dashboard/
    └── server.js                   # 📊 Live web dashboard (Use Case 10)
```

---

## 17. How to Run — Step by Step

### Step 1: Start Kafka Infrastructure

```bash
cd fintech-kafka
docker compose up -d
docker compose ps          # Wait until all healthy
```

### Step 2: Install Dependencies

```bash
npm install
```

### Step 3: Create Topics

```bash
node setup/create-topics.js
```

### Step 4: Start All Services (each in a separate terminal)

```bash
# Terminal 1 — Fraud Detection
node fraud/fraud-detector.js

# Terminal 2 — Payment Processor
node payments/payment-processor.js

# Terminal 3 — Ledger
node ledger/ledger-service.js

# Terminal 4 — Portfolio Tracker
node portfolio/portfolio-tracker.js

# Terminal 5 — Notifications
node notifications/notification-service.js

# Terminal 6 — Audit Compliance
node compliance/audit-service.js

# Terminal 7 — Dashboard (http://localhost:3000)
node dashboard/server.js
```

### Step 5: Trigger Payments

```bash
# Terminal 8 — Send test payments
node payments/initiate-payment.js

# Or via dashboard API:
curl -X POST http://localhost:3000/api/payment \
  -H "Content-Type: application/json" \
  -d '{"senderId":"USER-001","receiverId":"USER-002","amount":250}'

# Or open http://localhost:3000 and use the UI
```

### Step 6: Try KYC & Settlement

```bash
# Submit KYC (Terminal 9)
node kyc/submit-kyc.js

# Settlement runs automatically every 30 seconds
node settlement/settlement-service.js
```

### Full Pipeline Flow

```
Payment Initiated
    → Rate Limiter (Use Case 8)
        → Fraud Detection (Use Case 2)
            → Payment Processor (Use Case 1)
                → Ledger Service (Use Case 4)
                → Portfolio Tracker (Use Case 5)
                → Notification Engine (Use Case 6)
                → Audit Trail (Use Case 7)
                → Settlement Accumulator (Use Case 9)
    → Dashboard (Use Case 10) — sees everything in real-time
```

### Cleanup

```bash
docker compose down -v
```

---

**Built for FinTech. Powered by Kafka. 🏦⚡**
