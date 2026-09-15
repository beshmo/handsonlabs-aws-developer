# Lab D1-T1-L02 — Decoupling Services with Amazon SQS

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes
**Skills Practiced (primary):**
- `1.1.3` — Describe differences between tightly coupled and loosely coupled components
- `1.1.8` — Write code to use messaging services

**Skills Practiced (secondary, cross-referenced):**
- `1.1.4` (see Domain 1 Task 1) — Describe differences between synchronous and asynchronous patterns

**AWS Services Used:** Amazon Simple Queue Service (Amazon SQS), AWS Lambda, AWS Identity and Access Management (IAM), Amazon CloudWatch Logs, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials). Completion of `D1-T1-L01` is helpful but not required — no leftover resources from that lab are used here.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- Lambda: max 256 MB memory, max 10 s timeout, no container images.
- SQS: standard queue, basic operations only — no special configuration needed.
- IAM: create a purpose-scoped role rather than reusing an existing broad-permission role.

## Purpose

A producer that calls a consumer directly is *tightly coupled* — if the consumer is slow, down, or renamed, the producer breaks too. Amazon SQS breaks that dependency: the producer only needs to know a queue exists, and the consumer only needs to know how to read from it. In this lab you'll build exactly that: a producer that sends messages to a queue with zero knowledge of who (or what) reads them, and an AWS Lambda function wired to the queue as an independent consumer via an event source mapping. You'll see that sending a message returns immediately (asynchronous hand-off) while the actual processing happens later, on its own schedule — the concrete difference between loosely/tightly coupled and synchronous/asynchronous that the exam asks you to describe.

## Steps

1. **Open CloudShell and set shared variables:**
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$(date +%s)
   export QUEUE_NAME="dva-decouple-demo-${SUFFIX}"
   export FUNCTION_NAME="dva-decouple-consumer-${SUFFIX}"
   export ROLE_NAME="dva-decouple-role-${SUFFIX}"
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   echo "$QUEUE_NAME / $FUNCTION_NAME / $ROLE_NAME / $ACCOUNT_ID"
   ```

2. **Create the SQS queue (the decoupling point)** — this is the only thing the producer will ever know about:
   ```bash
   aws sqs create-queue --queue-name "$QUEUE_NAME" --region "$AWS_REGION"
   export QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --query QueueUrl --output text)
   export QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
   echo "$QUEUE_URL / $QUEUE_ARN"
   ```

3. **Create a least-privilege execution role for the consumer Lambda** — write the trust policy, create the role, then attach an inline policy scoped only to this queue and this function's log group:
   ```bash
   cat > trust-policy.json << 'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}
     ]
   }
   EOF
   aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json

   cat > exec-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
         "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/${FUNCTION_NAME}:*"
       },
       {
         "Effect": "Allow",
         "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
         "Resource": "${QUEUE_ARN}"
       }
     ]
   }
   EOF
   aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "dva-decouple-exec-policy" --policy-document file://exec-policy.json
   ```
   This is skill 2.1.6 in miniature (least-privilege IAM), but the point here is that the *consumer's* permissions are entirely separate from the *producer's* — another dimension of loose coupling.

4. **Write and deploy the consumer Lambda function** — it only knows how to process one SQS message at a time; it has no idea who produced it:
   ```bash
   cat > lambda_function.py << 'EOF'
   import json

   def lambda_handler(event, context):
       for record in event["Records"]:
           body = json.loads(record["body"])
           print(f"Consumed message: {body}")
       return {"processed": len(event["Records"])}
   EOF
   zip function.zip lambda_function.py

   sleep 10  # allow the new IAM role to propagate before Lambda tries to assume it

   aws lambda create-function \
       --function-name "$FUNCTION_NAME" \
       --runtime python3.11 \
       --role "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://function.zip \
       --timeout 10 \
       --memory-size 128
   ```

5. **Wire the queue to the function with an event source mapping** — this is the piece that makes SQS actively push work to Lambda instead of Lambda having to poll manually:
   ```bash
   export MAPPING_UUID=$(aws lambda create-event-source-mapping \
       --function-name "$FUNCTION_NAME" \
       --event-source-arn "$QUEUE_ARN" \
       --batch-size 5 \
       --query UUID --output text)
   echo "$MAPPING_UUID"
   ```

6. **Act as the producer — send messages knowing nothing about the consumer.** Notice each call returns instantly with a `MessageId`; the producer does not wait for (or know about) processing. This is the async, loosely-coupled hand-off (skills 1.1.4, 1.1.3):
   ```bash
   aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"order_id": 1, "item": "keyboard"}'
   aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"order_id": 2, "item": "mouse"}'
   aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"order_id": 3, "item": "monitor"}'
   ```

7. **Give the event source mapping a few seconds to poll and invoke**, then check the consumer's logs:
   ```bash
   sleep 20
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
       --query 'events[*].message' --output text
   ```

## Validation

- Each `send-message` call returned a `MessageId` immediately (no error, no wait for a consumer response) — proof of the asynchronous hand-off.
- `aws logs filter-log-events` shows three `Consumed message: {...}` lines with `order_id` 1, 2, and 3 — proof the Lambda consumer processed every message the producer sent, despite the producer never referencing Lambda, the function name, or the IAM role at any point.
- `aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages` returns `0` once processing has finished, confirming the queue drained.

## Cleanup

```bash
aws lambda delete-event-source-mapping --uuid "$MAPPING_UUID"
aws lambda delete-function --function-name "$FUNCTION_NAME"
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "dva-decouple-exec-policy"
aws iam delete-role --role-name "$ROLE_NAME"
aws sqs delete-queue --queue-url "$QUEUE_URL"
rm -f trust-policy.json exec-policy.json lambda_function.py function.zip
```
Confirm teardown:
```bash
aws sqs get-queue-url --queue-name "$QUEUE_NAME"   # should error: QueueDoesNotExist
aws lambda get-function --function-name "$FUNCTION_NAME"   # should error: ResourceNotFoundException
```

## References

- AWS CLI `sqs create-queue` / `send-message` / `delete-queue` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/sqs/create-queue.rst, https://github.com/aws/aws-cli/blob/develop/awscli/examples/sqs/send-message.rst, https://github.com/aws/aws-cli/blob/develop/awscli/examples/sqs/delete-queue.rst
- AWS CLI `sqs get-queue-attributes` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/sqs/get-queue-attributes.rst
- AWS CLI `iam create-role` / `put-role-policy` / `delete-role` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/iam/create-role.rst, https://github.com/aws/aws-cli/blob/develop/awscli/examples/iam/put-role-policy.rst, https://github.com/aws/aws-cli/blob/develop/awscli/examples/iam/delete-role.rst
- AWS CLI `lambda create-function` (Python runtime, IAM role propagation delay pattern) — https://docs.aws.amazon.com/cli/latest/userguide/bash_sts_code_examples.md
- AWS CLI `lambda create-event-source-mapping` / `delete-event-source-mapping` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/lambda/create-event-source-mapping.rst, https://github.com/aws/aws-cli/blob/develop/awscli/examples/lambda/delete-event-source-mapping.rst
- CloudWatch Logs `FilterLogEvents` API — https://github.com/aws/aws-cli/blob/develop/awscli/botocore/data/logs/2014-03-28/service-2.json
