# Lab D1-T1-L03 — Fan-Out Messaging with SNS + SQS

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.1` — Describe architectural patterns (for example, event-driven, microservices, monolithic, choreography, orchestration, fanout)
- `1.1.4` — Describe differences between synchronous and asynchronous patterns

**Skills Practiced (secondary, cross-referenced):**
- `1.1.8` (see Domain 1 Task 1) — Write code to use messaging services

**AWS Services Used:** Amazon Simple Notification Service (Amazon SNS), Amazon Simple Queue Service (Amazon SQS), AWS CLI, AWS SDK (boto3)
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials; ships with `python3`, `boto3`, and `jq`). Conceptual familiarity with SQS queues (see `D1-T1-L02`) — no resources from that lab are used here.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- SNS and SQS: standard topic/queues, basic operations only — no FIFO, no encryption, no cross-account access needed.
- No Lambda, EC2, or IAM roles are created, so none of the Lambda/IAM playground restrictions come into play. The only access policy is a *queue resource policy* set with `sqs set-queue-attributes`.

## Purpose

In a fan-out architecture, one event is published once and delivered to many independent consumers. Here an "order service" publishes a single `order_placed` event to an Amazon SNS topic, and three SQS queues subscribed to that topic each receive their own copy — so inventory, notifications, and fraud review can each process it on their own schedule, and adding a fourth consumer requires no change to the publisher. You'll also compare raw versus wrapped (envelope) delivery and use a subscription filter policy so one consumer only sees high-priority orders. Along the way you'll see the asynchronous, push-then-buffer behavior that separates this pattern from a direct, synchronous call to each consumer.

## Steps

1. **Set shared variables in CloudShell** — one suffix keeps every resource name unique and easy to clean up:
   ```bash
   export AWS_REGION=us-east-1
   export AWS_DEFAULT_REGION=us-east-1
   export SUFFIX=$(date +%s)
   export TOPIC_NAME="dva-orders-topic-${SUFFIX}"
   export INV_NAME="dva-inventory-q-${SUFFIX}"
   export NOTIFY_NAME="dva-notifications-q-${SUFFIX}"
   export FRAUD_NAME="dva-fraud-review-q-${SUFFIX}"
   echo "$TOPIC_NAME"
   ```

2. **Create the SNS topic (the fan-out point)** — the publisher will know only this topic, never the consumers (skill 1.1.1, fanout):
   ```bash
   export TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text)
   echo "$TOPIC_ARN"
   ```

3. **Create three SQS queues and let the topic write to them** — an SNS topic can only deliver to a queue whose resource policy allows `sns.amazonaws.com` to call `sqs:SendMessage`, scoped by `aws:SourceArn` to this one topic (least privilege). The helper below creates a queue, builds that policy, and applies it:
   ```bash
   make_queue() {   # $1 = queue name; prints "<queue-url> <queue-arn>"
     local url arn
     url=$(aws sqs create-queue --queue-name "$1" --query QueueUrl --output text)
     arn=$(aws sqs get-queue-attributes --queue-url "$url" \
         --attribute-names QueueArn --query Attributes.QueueArn --output text)
     jq -n --arg arn "$arn" --arg topic "$TOPIC_ARN" '{
       Version: "2012-10-17",
       Statement: [{
         Effect: "Allow",
         Principal: {Service: "sns.amazonaws.com"},
         Action: "sqs:SendMessage",
         Resource: $arn,
         Condition: {ArnEquals: {"aws:SourceArn": $topic}}
       }]}' > policy.json
     # the Policy attribute value must be the policy document as a JSON *string*
     jq -n --arg p "$(cat policy.json)" '{Policy: $p}' > attrs.json
     aws sqs set-queue-attributes --queue-url "$url" --attributes file://attrs.json
     echo "$url $arn"
   }

   read INV_URL    INV_ARN    <<< "$(make_queue "$INV_NAME")"
   read NOTIFY_URL NOTIFY_ARN <<< "$(make_queue "$NOTIFY_NAME")"
   read FRAUD_URL  FRAUD_ARN  <<< "$(make_queue "$FRAUD_NAME")"
   echo "$INV_ARN / $NOTIFY_ARN / $FRAUD_ARN"
   ```

4. **Subscribe each queue to the topic, with different delivery behavior** — subscriptions are where the consumers differ, not the publisher (skill 1.1.1). SQS subscriptions in the same account are confirmed automatically:
   ```bash
   # Inventory: receives every message, delivered as-is (raw)
   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
       --notification-endpoint "$INV_ARN" \
       --attributes RawMessageDelivery=true

   # Notifications: receives every message, wrapped in the standard SNS JSON envelope (default)
   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
       --notification-endpoint "$NOTIFY_ARN"

   # Fraud review: receives ONLY messages whose "priority" attribute is "high", delivered raw
   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
       --notification-endpoint "$FRAUD_ARN" \
       --attributes '{"RawMessageDelivery":"true","FilterPolicy":"{\"priority\":[\"high\"]}"}'
   ```
   `RawMessageDelivery=true` hands the consumer just the message body; without it, SNS wraps the body plus metadata in a JSON envelope. `FilterPolicy` is evaluated by SNS against message attributes (the default `FilterPolicyScope`), so non-matching messages are never delivered to that queue.

5. **Write the publisher (the "order service")** — a short boto3 script that publishes once per order. Each `publish` call returns as soon as SNS has accepted the message; it does not wait for any consumer, which is the asynchronous hand-off (skills 1.1.4, 1.1.8):
   ```bash
   cat > publish.py << 'EOF'
   import json, os
   import boto3

   sns = boto3.client("sns", region_name="us-east-1")
   topic_arn = os.environ["TOPIC_ARN"]

   orders = [
       {"order_id": 1, "total": 950, "priority": "high"},
       {"order_id": 2, "total": 12,  "priority": "low"},
   ]

   for order in orders:
       resp = sns.publish(
           TopicArn=topic_arn,
           Message=json.dumps(order),
           MessageAttributes={
               "priority": {"DataType": "String", "StringValue": order["priority"]}
           },
       )
       print(f"Published order {order['order_id']} ({order['priority']}) -> MessageId {resp['MessageId']}")
   EOF
   python3 publish.py
   ```
   Two events are published; the publisher references no queue, consumer, or count of subscribers.

6. **Write a consumer that drains a queue** — a generic long-polling reader you'll point at each queue in turn. It unwraps the SNS envelope when present and deletes each message after processing (skill 1.1.8):
   ```bash
   cat > drain.py << 'EOF'
   import json, sys
   import boto3

   sqs = boto3.client("sqs", region_name="us-east-1")
   queue_url = sys.argv[1]

   while True:
       resp = sqs.receive_message(
           QueueUrl=queue_url,
           MaxNumberOfMessages=10,
           WaitTimeSeconds=5,            # long polling
           MessageAttributeNames=["All"],
       )
       messages = resp.get("Messages", [])
       if not messages:
           break
       for m in messages:
           body = json.loads(m["Body"])
           if body.get("Type") == "Notification":       # SNS envelope
               print(f"[envelope] Message={body['Message']}  envelope-keys={sorted(body)}")
           else:                                        # raw delivery
               print(f"[raw]      {body}")
           sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=m["ReceiptHandle"])
   EOF
   ```

7. **Read all three queues and compare** — same publisher, three different outcomes:
   ```bash
   echo "--- inventory (all, raw) ---";           python3 drain.py "$INV_URL"
   echo "--- notifications (all, envelope) ---";  python3 drain.py "$NOTIFY_URL"
   echo "--- fraud review (filtered, raw) ---";   python3 drain.py "$FRAUD_URL"
   ```
   Inventory and notifications each print both orders; fraud review prints only order 1. The notifications output shows the envelope keys (`Type`, `MessageId`, `TopicArn`, `Message`, `MessageAttributes`, `Timestamp`, ...), while inventory shows just the order JSON.

## Validation

- Both `publish` calls in step 5 returned a `MessageId` immediately, without any consumer having been read yet — the publisher is decoupled from (and asynchronous to) its subscribers.
- Step 7 output shows:
  - `inventory` → `[raw] {'order_id': 1, ...}` and `[raw] {'order_id': 2, ...}` (fan-out: one publish, a copy per subscribed queue)
  - `notifications` → two `[envelope]` lines, each with `Message={"order_id": ...}` (same event, wrapped in the SNS envelope)
  - `fraud review` → exactly one `[raw]` line, for `order_id` 1 (filter policy dropped the `low` priority order)
- Confirm the subscriptions and filter policy:
  ```bash
  aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
      --query 'Subscriptions[*].[Endpoint,SubscriptionArn]' --output table
  ```
  shows three confirmed subscription ARNs (none `PendingConfirmation`).

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
# Deleting the topic also deletes its subscriptions
aws sns delete-topic --topic-arn "$TOPIC_ARN"
aws sqs delete-queue --queue-url "$INV_URL"
aws sqs delete-queue --queue-url "$NOTIFY_URL"
aws sqs delete-queue --queue-url "$FRAUD_URL"
rm -f policy.json attrs.json publish.py drain.py
```

Confirm teardown:
```bash
aws sns get-topic-attributes --topic-arn "$TOPIC_ARN"   # should error: NotFound
aws sqs get-queue-url --queue-name "$INV_NAME"          # should error: QueueDoesNotExist
```

## References

- AWS CLI `sns create-topic` / `delete-topic` — https://docs.aws.amazon.com/cli/latest/reference/sns/create-topic.html, https://docs.aws.amazon.com/cli/latest/reference/sns/delete-topic.html
- AWS CLI `sns subscribe` (`--notification-endpoint`, `RawMessageDelivery`, `FilterPolicy`, `FilterPolicyScope`) — https://docs.aws.amazon.com/cli/latest/reference/sns/subscribe.html
- AWS CLI `sns publish` (`--message-attributes` structure: `DataType`, `StringValue`) — https://docs.aws.amazon.com/cli/latest/reference/sns/publish.html
- AWS CLI `sns list-subscriptions-by-topic` — https://docs.aws.amazon.com/cli/latest/userguide/bash_sns_code_examples.md
- AWS CLI `sqs set-queue-attributes` (`Policy` attribute, `--attributes file://`) — https://docs.aws.amazon.com/cli/latest/reference/sqs/set-queue-attributes.html
- AWS CLI `sqs receive-message` — https://docs.aws.amazon.com/cli/latest/reference/sqs/receive-message.html
- Boto3 SQS guide (`receive_message` with `WaitTimeSeconds`, `MessageAttributeNames`, `delete_message`) — https://github.com/boto/boto3/blob/develop/docs/source/guide/sqs-example-sending-receiving-msgs.rst, https://github.com/boto/boto3/blob/develop/docs/source/guide/sqs-example-long-polling.rst
