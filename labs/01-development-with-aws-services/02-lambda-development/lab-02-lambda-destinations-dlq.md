# Lab D1-T2-L02 — Lambda Error Handling: Synchronous Errors and Dead-Letter Queues

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 2 — Develop code for AWS Lambda
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.2.3` — Handle the event lifecycle and errors by using code (for example, Lambda Destinations, dead-letter queues)

**Skills Practiced (secondary, cross-referenced):**
- None

**AWS Services Used:** AWS Lambda, Amazon SQS, Amazon SNS, AWS Identity and Access Management (IAM), Amazon CloudWatch, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CLI v2 configured against the KodeKloud playground credentials (for example AWS CloudShell, or a local shell with the `kk_labs_user_*` access keys); `zip` available; conceptual familiarity with Python and with the difference between synchronous and asynchronous Lambda invocation. Be ready for one ~2-4 minute wait (Lambda's async retry back-off) in the middle of the lab. No resources from any other lab are used.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- Lambda: max 256 MB memory, max 10 s timeout, max ~300 invocations/hour, no container images. This lab uses 128 MB, a 10 s timeout, and three invocation requests in total (each failed async event is retried twice by Lambda, so about seven executions overall).
- IAM: you can create a role and attach AWS managed policies, but inline role policies (`iam:PutRolePolicy`) are denied, so this lab attaches managed policies only. A role passed to Lambda must be created under `--path /service-role/` (`iam:PassRole` is denied at the default `/` path).
- SQS and SNS: basic operations only. Creating queues and topics, `sqs:SetQueueAttributes` with a queue policy for `sns.amazonaws.com`, and an SNS-to-SQS subscription are confirmed working in the playground; this lab uses two small standard queues and one standard topic.
- Lambda Destinations are **not available**: `lambda:PutFunctionEventInvokeConfig` and `lambda:UpdateFunctionEventInvokeConfig` are denied, so OnSuccess/OnFailure destinations and per-function async retry/max-event-age settings cannot be configured. This lab therefore teaches function-level dead-letter queues only, with the default async retry behavior (2 retries).
- CloudWatch Logs: `logs:DeleteLogGroup` is denied, so the function's log group remains until the session ends.

## Purpose

Lambda treats a failure differently depending on how it was invoked: a synchronous invocation returns the error to the caller, while an asynchronous invocation (for example from S3, SNS, EventBridge, or `--invocation-type Event`) is retried twice with back-off and then discarded unless a dead-letter queue (DLQ) is configured. In this lab you deploy a function that fails on demand, invoke it both ways, and configure a function-level DLQ in two flavours, an SQS queue and an SNS topic fanned out to an SQS queue, then compare what each one captures. This is the event-lifecycle and error-handling behavior the exam tests when it asks about DLQs.

> **Playground note:** Lambda Destinations (OnSuccess/OnFailure, set with `put-function-event-invoke-config`) are denied in the KodeKloud playground, so they are not part of this lab. Know for the exam that Destinations are the newer mechanism (they handle success and failure and carry the response/error detail), while the DLQ is the older, failure-only mechanism configured on the function itself.

## Steps

1. **Set shared variables** — a random suffix keeps all names unique within the account:
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$RANDOM
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export ROLE_NAME="dva-order-processor-role-${SUFFIX}"
   export FN_SQS="dva-fn-dlq-sqs-${SUFFIX}"
   export FN_SNS="dva-fn-dlq-sns-${SUFFIX}"
   export DLQ_SQS_Q="dva-dlq-direct-${SUFFIX}"
   export DLQ_SNS_Q="dva-dlq-capture-${SUFFIX}"
   export DLQ_TOPIC="dva-dlq-topic-${SUFFIX}"
   ```
   > *Optional:* in Windows Git Bash also run `export MSYS_NO_PATHCONV=1` so `--path /service-role/` is not rewritten into a Windows path.

2. **Create the dead-letter targets (skill 1.2.3)** — a function-level DLQ must be an SQS queue or an SNS topic. Queue 1 will be a DLQ directly. For the topic, an SNS topic cannot be read directly, so subscribe queue 2 to it and give SNS permission to write to that queue:
   ```bash
   # Target A: SQS queue used directly as the DLQ
   export DLQ_SQS_URL=$(aws sqs create-queue --queue-name "$DLQ_SQS_Q" --query QueueUrl --output text)
   export DLQ_SQS_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ_SQS_URL" \
       --attribute-names QueueArn --query Attributes.QueueArn --output text)

   # Target B: SNS topic as the DLQ, fanned out to a capture queue
   export TOPIC_ARN=$(aws sns create-topic --name "$DLQ_TOPIC" --query TopicArn --output text)
   export DLQ_SNS_URL=$(aws sqs create-queue --queue-name "$DLQ_SNS_Q" --query QueueUrl --output text)
   export DLQ_SNS_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ_SNS_URL" \
       --attribute-names QueueArn --query Attributes.QueueArn --output text)

   cat > dlq-queue-attrs.json << EOF
   {
     "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"${DLQ_SNS_ARN}\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"${TOPIC_ARN}\"}}}]}"
   }
   EOF
   aws sqs set-queue-attributes --queue-url "$DLQ_SNS_URL" --attributes file://dlq-queue-attrs.json

   aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$DLQ_SNS_ARN"
   ```

3. **Create the execution role (skill 1.2.3)** — Lambda sends DLQ messages using the function's execution role, so the role needs permission to write to SQS and SNS. Inline policies are denied in the playground, so attach the AWS managed policies `AWSLambdaBasicExecutionRole` (logs), `AmazonSQSFullAccess` (`sqs:SendMessage` for target A) and `AmazonSNSFullAccess` (`sns:Publish` for target B). In a real account you would use a customer-managed or inline policy scoped to just this queue and this topic. Create the role under `/service-role/`:
   ```bash
   cat > trust-policy.json << 'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}
     ]
   }
   EOF
   aws iam create-role --role-name "$ROLE_NAME" --path /service-role/ \
       --assume-role-policy-document file://trust-policy.json

   aws iam attach-role-policy --role-name "$ROLE_NAME" \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   aws iam attach-role-policy --role-name "$ROLE_NAME" \
       --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
   aws iam attach-role-policy --role-name "$ROLE_NAME" \
       --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
   ```
   > **Playground note:** the `/service-role/` path is required because the playground allows `iam:PassRole` for Lambda only on that path.

4. **Deploy two copies of a function that fails on demand (skill 1.2.3)** — the handler raises an exception when the event contains `"fail": true`; otherwise it returns a result. A raised exception is what Lambda treats as a failed invocation. A function has only one DLQ, so create two identically coded functions to compare the two targets side by side:
   ```bash
   cat > lambda_function.py << 'EOF'
   def lambda_handler(event, context):
       if event.get("fail"):
           raise ValueError(f"Order {event.get('order_id')} could not be processed")
       return {"order_id": event.get("order_id"), "status": "PROCESSED"}
   EOF
   zip function.zip lambda_function.py

   sleep 10  # allow the new IAM role to propagate before Lambda tries to assume it

   for FN in "$FN_SQS" "$FN_SNS"; do
     aws lambda create-function \
         --function-name "$FN" \
         --runtime python3.12 \
         --role "arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ROLE_NAME}" \
         --handler lambda_function.lambda_handler \
         --zip-file fileb://function.zip \
         --timeout 10 \
         --memory-size 128
     aws lambda wait function-active-v2 --function-name "$FN"
   done
   ```

5. **Configure a different DLQ on each function (skill 1.2.3)** — the DLQ is configured on the function itself (`DeadLetterConfig`) and receives the original event of an asynchronous invocation only after all retries are exhausted. Function A points at the SQS queue, function B at the SNS topic:
   ```bash
   aws lambda update-function-configuration --function-name "$FN_SQS" \
       --dead-letter-config "TargetArn=${DLQ_SQS_ARN}"
   aws lambda wait function-updated-v2 --function-name "$FN_SQS"

   aws lambda update-function-configuration --function-name "$FN_SNS" \
       --dead-letter-config "TargetArn=${TOPIC_ARN}"
   aws lambda wait function-updated-v2 --function-name "$FN_SNS"
   ```

6. **Invoke synchronously with a bad event (skill 1.2.3)** — with `RequestResponse` (the default), the caller waits and receives the error directly. There is nothing to retry or dead-letter; handling the error is the caller's job. AWS CLI v2 needs `--cli-binary-format raw-in-base64-out` for a literal JSON payload:
   ```bash
   aws lambda invoke --function-name "$FN_SQS" --invocation-type RequestResponse \
       --cli-binary-format raw-in-base64-out \
       --payload '{"order_id":"1001","fail":true}' out-sync.json
   cat out-sync.json
   ```
   The CLI prints `"StatusCode": 200` together with `"FunctionError": "Unhandled"`, and `out-sync.json` contains `errorMessage` ("Order 1001 could not be processed") and `errorType` (`ValueError`). Nothing is sent to the DLQ for this invocation.

7. **Invoke asynchronously with a bad event on both functions (skill 1.2.3)** — `--invocation-type Event` queues the event and returns `202` immediately; the function result is never returned to the caller, which is why DLQs exist. Invoke both functions now so the two retry cycles run in parallel:
   ```bash
   aws lambda invoke --function-name "$FN_SQS" --invocation-type Event \
       --cli-binary-format raw-in-base64-out \
       --payload '{"order_id":"1002","fail":true}' out-async-sqs.json

   aws lambda invoke --function-name "$FN_SNS" --invocation-type Event \
       --cli-binary-format raw-in-base64-out \
       --payload '{"order_id":"1003","fail":true}' out-async-sns.json
   ```
   Both calls print `"StatusCode": 202`, even though the function will fail.

8. **Wait for the retries, then read the SQS-target DLQ (skill 1.2.3)** — with no per-function retry configuration (that API is denied in the playground), Lambda applies the default of 2 retries with back-off, so the event reaches the DLQ about **2 to 4 minutes** after the invoke. This is expected, not an error. Poll with long polling; the loop below checks every 20 seconds for up to 6 minutes and stops as soon as a message arrives:
   ```bash
   for i in $(seq 1 18); do
     MSG=$(aws sqs receive-message --queue-url "$DLQ_SQS_URL" --wait-time-seconds 20 \
         --max-number-of-messages 1 --message-attribute-names All --output json)
     [ -n "$MSG" ] && echo "$MSG" | grep -q '"Messages"' && break
     echo "attempt $i: no message yet"
   done
   echo "$MSG"
   ```
   While it runs, you can open the function's CloudWatch Logs group in another terminal to see three START/END pairs for order 1002 (the original attempt plus two retries). The message `Body` is exactly the original event (`{"order_id":"1002","fail":true}`). The failure reason travels in the message attributes `ErrorCode`, `ErrorMessage` and `RequestID`. If the loop exits without a message, run it again (the retries may simply still be pending).

9. **Read the SNS-target DLQ and compare (skill 1.2.3)** — function B's retries ran in parallel with A's, so its event should already be in the capture queue:
   ```bash
   aws sqs receive-message --queue-url "$DLQ_SNS_URL" --wait-time-seconds 20 \
       --max-number-of-messages 1 --message-attribute-names All \
       --query 'Messages[0].Body' --output text
   ```
   The SNS envelope's `Message` field holds the original event (`{"order_id":"1003","fail":true}`), and the error code, error message and `RequestID` appear inside the envelope's `MessageAttributes`. Compare the two targets: the SQS queue delivers the event with the attributes on the SQS message itself, while the SNS topic wraps it in an SNS notification envelope and can fan out to several subscribers (email, Lambda, more queues). In both cases only failures after all retries are captured, with the original request but no response payload or success record, which is the gap Destinations were later introduced to fill.

10. **Confirm the configuration** — the DLQ target of each function:
    ```bash
    aws lambda get-function-configuration --function-name "$FN_SQS" --query DeadLetterConfig
    aws lambda get-function-configuration --function-name "$FN_SNS" --query DeadLetterConfig
    ```

## Validation

- Step 6 returned `StatusCode` 200 with `FunctionError` `Unhandled` and the error detail in `out-sync.json`, and the DLQs received nothing for order 1001: a synchronous error goes back to the caller.
- Step 7 returned `StatusCode` 202 for both invocations, proving they were asynchronous.
- The SQS DLQ queue holds one message whose body is the failed event for order 1002, with `ErrorCode`, `ErrorMessage` and `RequestID` message attributes; it arrived about 2 to 4 minutes after the invoke because of the default retries.
- The SNS-fed capture queue holds one message wrapping the failed event for order 1003, with the error details in the envelope's `MessageAttributes`.
- `get-function-configuration` shows `DeadLetterConfig.TargetArn` as the queue ARN for the first function and the topic ARN for the second.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
# 1. Delete the functions
aws lambda delete-function --function-name "$FN_SQS"
aws lambda delete-function --function-name "$FN_SNS"

# 2. Delete the SNS topic (removes its subscription), then the queues
aws sns delete-topic --topic-arn "$TOPIC_ARN"
aws sqs delete-queue --queue-url "$DLQ_SNS_URL"
aws sqs delete-queue --queue-url "$DLQ_SQS_URL"

# 3. Detach the managed policies, then delete the role
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam delete-role --role-name "$ROLE_NAME"

rm -f function.zip lambda_function.py trust-policy.json dlq-queue-attrs.json out-sync.json out-async-sqs.json out-async-sns.json
```

The functions' CloudWatch Logs groups (`/aws/lambda/<function name>`) are left behind by Lambda. The playground denies `logs:DeleteLogGroup`, so they simply remain until your session ends.

## References

- AWS CLI `lambda update-function-configuration` (`--dead-letter-config`, SQS queue or SNS topic `TargetArn`) — https://docs.aws.amazon.com/cli/latest/reference/lambda/update-function-configuration.html
- AWS CLI `lambda invoke` — https://docs.aws.amazon.com/cli/latest/reference/lambda/invoke.html
- Lambda Developer Guide: capturing records of asynchronous invocations (DLQ and Destinations) — https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-retain-records.html
- Lambda Developer Guide: configuring asynchronous invocation (retries, event age) — https://docs.aws.amazon.com/lambda/latest/dg/invocation-async-configuring.html
- AWS CLI `sqs receive-message` — https://docs.aws.amazon.com/cli/latest/reference/sqs/receive-message.html
- AWS CLI `sqs get-queue-attributes` — https://docs.aws.amazon.com/cli/latest/reference/sqs/get-queue-attributes.html
