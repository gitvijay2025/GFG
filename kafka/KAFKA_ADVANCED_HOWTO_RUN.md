# Understanding Kafka Advanced Patterns — Run Guide & Recommendations

> How to run each example, what depends on what, and the recommended learning path.

---

## 🧠 First — The Big Picture

There are **TWO separate projects** in this workspace:

| Document | Type | How Services Connect |
|----------|------|----------------------|
| **KAFKA_NODEJS_GUIDE.md** | Learning examples (basic → advanced) | Each example runs **independently** |
| **KAFKA_FINTECH_GUIDE.md** | Real-world FinTech project | All services form **one connected pipeline** |

---

## Part 1: KAFKA_NODEJS_GUIDE — Independent Examples

### Rule: Each example (3.x, 4.x, 5.x) is a **standalone demo**. They do NOT depend on each other.

```
                    ┌──────────────────────────────┐
                    │   STEP 0: DO THIS ONCE       │
                    │                              │
                    │   docker compose up -d       │
                    │   npm install                │
                    │   node advanced/admin-client.js │ ← Creates all topics
                    └──────────────┬───────────────┘
                                   │
                    After Step 0, pick ANY example:
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
          ▼                        ▼                        ▼
   ┌─────────────┐        ┌──────────────┐         ┌──────────────┐
   │   BASIC     │        │ INTERMEDIATE │         │   ADVANCED   │
   │  (Level 1)  │        │  (Level 2)   │         │  (Level 3)   │
   └─────────────┘        └──────────────┘         └──────────────┘
```

---

### 📗 BASIC LEVEL — Run Order

| # | Example | Terminals Needed | Command |
|---|---------|-----------------|---------|
| 3.1 | Simple Producer | 1 | `node basic/producer.js` |
| 3.2 | Simple Consumer | 1 (keep running) | `node basic/consumer.js` |
| 3.3 | Consumer Groups | 3 | `node basic/consumer-group.js 1` (T1), `…2` (T2), then produce (T3) |

**Recommended order:** Run 3.1 first, then 3.2 — you'll see the message appear. Then try 3.3.

```
HOW 3.1 + 3.2 work together:
─────────────────────────────
  Terminal 1:  node basic/consumer.js     ← Waiting for messages...
  Terminal 2:  node basic/producer.js     ← Sends "Hello Kafka!"

  Result: Terminal 1 prints the message instantly.

HOW 3.3 works:
──────────────
  Terminal 1:  node basic/consumer-group.js 1    ← Consumer A
  Terminal 2:  node basic/consumer-group.js 2    ← Consumer B
  Terminal 3:  node basic/producer.js            ← Send messages

  Result: Messages are SPLIT between Consumer A and B.
          Each partition goes to only ONE consumer.
```

---

### 📙 INTERMEDIATE LEVEL — Run Order

| # | Example | Needs | Command |
|---|---------|-------|---------|
| 4.1 | Keyed Producer | — | `node intermediate/keyed-producer.js` |
| 4.2 | Batch Producer | — | `node intermediate/batch-producer.js` |
| 4.3 | Multi-Topic Consumer | Messages in 3 topics | Run 4.1 first, then `node intermediate/multi-topic-consumer.js` |
| 4.4 | Manual Offset | Messages in orders-topic | Run 4.1 first, then `node intermediate/manual-offset-consumer.js` |
| 4.5 | Resilient Producer | — | `node intermediate/resilient-producer.js` |

**Recommended order:** 4.1 → 4.2 → 4.3 → 4.4 → 4.5

```
4.1 and 4.2 are PRODUCERS — they just send messages and exit.
4.3, 4.4 are CONSUMERS — they read messages and stay running.
4.5 is a PRODUCER with retry logic.

TIP: Run a producer first to put data in topics, then start a consumer.
```

---

### 📕 ADVANCED LEVEL — Run Order

**⚠️ THIS IS THE IMPORTANT SECTION — READ CAREFULLY**

Every advanced example is **independent**. Here's exactly how each one works:

---

#### 5.1 — Exactly-Once Transactions

```
WHAT IT DOES:
  Reads from "raw-orders" → enriches → writes to "processed-orders" + "notifications"
  ALL THREE operations happen atomically (all succeed or all fail).

HOW TO RUN:
  Terminal 1:  node advanced/transactions.js          ← Waits for input

  Terminal 2:  Send raw orders manually:
    docker exec -it kafka-1 kafka-console-producer \
      --bootstrap-server localhost:9092 --topic raw-orders

    Then type (press Enter after each line):
    {"orderId":"ORD-1","userId":"user-1","amount":100}
    {"orderId":"ORD-2","userId":"user-2","amount":250}
    {"orderId":"ORD-3","userId":"user-3","amount":500}

  Terminal 1 will show: ✅ Transaction committed for ORD-1, ORD-2, ORD-3

FLOW:
  [raw-orders] → consumer → enrich → transaction.send([processed-orders])
                                    → transaction.send([notifications])
                                    → transaction.commit()  ← ALL or NOTHING
```

---

#### 5.2 — Dead Letter Queue

```
WHAT IT DOES:
  Reads from "orders-topic" → tries to process → if fails 3 times → sends to "orders-dlq"
  Orders with amount > $400 always fail (simulated).

HOW TO RUN:
  Terminal 1:  node advanced/dead-letter-queue.js     ← Waits for orders

  Terminal 2:  node intermediate/keyed-producer.js    ← Sends orders with random amounts

  Terminal 1 will show:
    ✅ for orders ≤ $400
    ⚠️ Retry 1/3, Retry 2/3 for orders > $400
    💀 Sent to DLQ after 3rd failure

FLOW:
  [orders-topic] → processOrder()
                      │
                   Success → commit offset → done
                   Failure → retry 1 → retry 2 → retry 3 → [orders-dlq]
```

---

#### 5.3 — Event Sourcing ⭐ (EASIEST — start here)

```
WHAT IT DOES:
  Creates a bank account, deposits money, withdraws money.
  Every action is stored as an EVENT. Account balance is rebuilt from events.

HOW TO RUN:
  Terminal 1:  node advanced/event-sourcing.js     ← Just this! Self-contained.

  It will automatically:
    1. Create account "John Doe"     → balance: $0
    2. Deposit $1000                 → balance: $1000
    3. Deposit $500                  → balance: $1500
    4. Withdraw $200                 → balance: $1300
    5. Withdraw $2000                → FAILS (insufficient funds)
    6. Print final state

NO SECOND TERMINAL NEEDED. It produces AND consumes.

FLOW:
  emitEvent() → [account-events] → consumer → eventHandler → update state
       ↑                                                          │
       └──────── same application ────────────────────────────────┘
```

---

#### 5.4 — Stream Processing

```
WHAT IT DOES:
  Reads IoT sensor data → aggregates in 10-second windows → emits averages.
  Like a mini "Kafka Streams" but in plain Node.js.

HOW TO RUN:
  Terminal 1:  node advanced/stream-processing.js    ← Starts aggregator

  Terminal 2:  node intermediate/batch-producer.js   ← Sends 1000 sensor readings

  Wait 10-15 seconds. Terminal 1 will show:
    📊 Window result: { deviceId: "device-0", avgTemperature: "27.34", ... }

FLOW:
  [iot-sensor-data] → aggregate by device + 10s window → [sensor-aggregated]
```

---

#### 5.5 — Schema Registry

```
WHAT IT DOES:
  Enforces message structure using Avro schemas.
  Producer MUST match the schema. Consumer auto-decodes.

HOW TO RUN:
  ⚠️ Requires Schema Registry container (port 8081). Make sure docker-compose
     includes the schema-registry service.

  Terminal 1:  node advanced/schema-registry.js

FLOW:
  Register schema → encode order as Avro → [avro-orders] → decode order from Avro
```

---

#### 5.6 — Admin Client (RUN THIS FIRST)

```
WHAT IT DOES:
  Creates all topics needed by every other example.

HOW TO RUN:
  Terminal 1:  node advanced/admin-client.js     ← Run once, it exits.

  ✅ This is the FIRST thing you should run after docker compose up.
```

---

#### 5.7 — Realtime Server ⭐ (MOST VISUAL)

```
WHAT IT DOES:
  Express web server + Kafka consumer + Server-Sent Events.
  Open browser → see live events as they happen.

HOW TO RUN:
  Terminal 1:  node advanced/realtime-server.js
  Browser:     http://localhost:3000

  Terminal 2:  Send test events:
    curl -X POST http://localhost:3000/api/orders \
      -H "Content-Type: application/json" \
      -d '{"userId":"user-1","amount":99.99}'

    curl -X POST http://localhost:3000/api/notifications \
      -H "Content-Type: application/json" \
      -d '{"type":"INFO","message":"Hello from Kafka!"}'

  Browser updates LIVE with each event.

FLOW:
  curl → Express API → producer → [orders-topic] → consumer → SSE → browser
```

---

## My Recommended Learning Path (Advanced)

```
START HERE (easiest)
      │
      ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.3 Event Sourcing     ← One terminal. Self-contained.     │
  │  Understand: events as source of truth, state from replay   │
  └──────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.7 Realtime Server    ← One terminal + browser.           │
  │  Understand: Kafka + Express + SSE = live updates           │
  └──────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.2 Dead Letter Queue  ← Two terminals.                    │
  │  Understand: handling failures without losing data           │
  └──────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.4 Stream Processing  ← Two terminals.                    │
  │  Understand: windowed aggregation, real-time analytics       │
  └──────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.1 Transactions       ← Two terminals + manual input.     │
  │  Understand: exactly-once, atomic multi-topic writes         │
  └──────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  5.5 Schema Registry    ← Needs extra Docker container.     │
  │  Understand: schema enforcement, Avro, backward compat      │
  └──────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                     NOW move to KAFKA_FINTECH_GUIDE.md
                     (all services connected together)
```

---

## Part 2: KAFKA_FINTECH_GUIDE — Connected Pipeline

Unlike the learning examples above, the FinTech guide has services that **talk to each other** through Kafka topics:

```
  initiate-payment.js → [payment.initiated]
                              │
                              ├──▶ fraud-detector.js → [payment.validated] OR [fraud.alerts]
                              │                              │
                              │                              ├──▶ payment-processor.js → [payment.completed]
                              │                              │         │
                              │                              │         ├──▶ [ledger.entries] → ledger-service.js
                              │                              │         ├──▶ [portfolio.updates] → portfolio-tracker.js
                              │                              │         ├──▶ [notifications] → notification-service.js
                              │                              │         └──▶ [audit.trail] → audit-service.js
                              │                              │
                              │                              └──▶ [payment.failed]
                              │
                              └──▶ [audit.trail] → audit-service.js

  SEPARATE FLOWS:
    submit-kyc.js → [kyc.verification] → kyc-service.js → [kyc.completed] + [notifications]
    settlement-service.js listens to [payment.completed] → aggregates → [settlement.completed]
    dashboard/server.js listens to ALL topics → live web UI
```

### How to Run the FinTech Pipeline

```bash
# ─── Step 1: Infrastructure ───
docker compose up -d
node setup/create-topics.js

# ─── Step 2: Start services (each in its own terminal) ───

# Terminal 1 — MUST start first (it feeds payment-processor)
node fraud/fraud-detector.js

# Terminal 2 — Processes validated payments
node payments/payment-processor.js

# Terminal 3 — Records ledger entries
node ledger/ledger-service.js

# Terminal 4 — Tracks portfolio balances
node portfolio/portfolio-tracker.js

# Terminal 5 — Sends notifications
node notifications/notification-service.js

# Terminal 6 — Writes audit log
node compliance/audit-service.js

# Terminal 7 — Web dashboard (http://localhost:3000)
node dashboard/server.js

# ─── Step 3: Trigger payments ───

# Terminal 8 — This kicks off the entire pipeline
node payments/initiate-payment.js
```

**Order matters here!** Start consumers (Terminals 1–7) BEFORE the producer (Terminal 8).

---

## Quick Reference — Terminal Count

| Example | Terminals | Difficulty |
|---------|-----------|------------|
| **Basic Guide** | | |
| 5.3 Event Sourcing | 1 | ⭐ Easy |
| 5.7 Realtime Server | 1 + browser | ⭐ Easy |
| 5.2 Dead Letter Queue | 2 | ⭐⭐ Medium |
| 5.4 Stream Processing | 2 | ⭐⭐ Medium |
| 5.1 Transactions | 2 + manual input | ⭐⭐⭐ Hard |
| 5.5 Schema Registry | 1 + extra Docker | ⭐⭐⭐ Hard |
| **FinTech Guide** | | |
| Full Pipeline | 8 terminals | ⭐⭐⭐⭐ Advanced |

---

## Common Mistakes to Avoid

| Mistake | Fix |
|---------|-----|
| Running examples without creating topics first | Run `node advanced/admin-client.js` first |
| Kafka not running | Run `docker compose up -d` and wait for healthy |
| Running consumer AFTER producer | Start consumer first, then produce |
| Thinking 5.1 and 5.2 are connected | They are independent — different topics, different patterns |
| Running FinTech services without fraud-detector | Start `fraud-detector.js` BEFORE `payment-processor.js` |
| Port 3000 already in use | Stop other Node servers or change the port |

---

## Summary

1. **Start with**: 5.3 (Event Sourcing) — one terminal, self-contained, instant results
2. **Then try**: 5.7 (Realtime Server) — visual, fun, easy to test
3. **Then learn**: 5.2 (DLQ) → 5.4 (Streams) → 5.1 (Transactions)
4. **Finally**: Move to **KAFKA_FINTECH_GUIDE.md** for the full connected pipeline
5. **Always run** `admin-client.js` or `create-topics.js` first after starting Docker

---

**Happy learning! 🚀**
