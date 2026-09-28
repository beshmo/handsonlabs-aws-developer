# Lab D1-T1-L08 — Streaming Data Processing with DynamoDB Streams and Lambda

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.10` — Handle streaming data using AWS services

**Skills Practiced (secondary, cross-referenced):**
- `1.2.7` (see Domain 1 Task 2) — Use Lambda functions to process and transform data in near real time

**AWS Services Used:** Amazon DynamoDB (DynamoDB Streams), AWS Lambda, AWS Identity and Access Management (IAM), Amazon CloudWatch Logs, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials). No leftover resources from another lab are required — this lab is fully self-contained.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- DynamoDB: `PAY_PER_REQUEST` (on-demand) billing mode — this lab creates exactly one table in that mode with a stream enabled.
- Lambda: max 256 MB memory, max 10 s timeout, no container images.
- IAM: you can create a role and attach AWS managed policies to it, but inline role policies (`iam:PutRolePolicy`) are denied — this lab attaches the AWS managed policy `AWSLambdaDynamoDBExecutionRole` instead. Lambda can only assume a role you create under the `/service-role/` path (`iam:PassRole` is denied on roles at the default `/` path).
- `lambda:DeleteEventSourceMapping` is denied in the playground — see the Cleanup note below.
- Note: Amazon Kinesis Data Streams is blocked outright in this playground by an org-level SCP (`kinesis:CreateStream` / `kinesis:ListStreams` return `AccessDeniedException`), so this lab uses DynamoDB Streams as its streaming mechanism instead.

## Purpose

DynamoDB Streams captures a time-ordered sequence of item-level modifications (inserts, updates, deletes) in a table and makes that change log available to consumers within seconds — a form of streaming data distinct from a message queue because it carries a full history of *what changed*, not just a discrete message. In this lab you create a DynamoDB table with a stream enabled, wire an AWS Lambda function to it as a poll-based consumer using an event source mapping (a DynamoDB Streams trigger), and generate `INSERT`, `MODIFY`, and `REMOVE` records with `put-item`, `update-item`, and `delete-item`. The Lambda function decodes each record's DynamoDB-JSON `NewImage`/`OldImage` and performs a small near-real-time transformation, demonstrating the core mechanic behind both "handle streaming data using AWS services" (1.1.10) and "use Lambda functions to process and transform data in near real time" (1.2.7).

## Steps

1. **Open CloudShell and set shared variables:**
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$(date +%s)
   export TABLE_NAME="dva-ddb-stream-demo-${SUFFIX}"
   export FUNCTION_NAME="dva-ddb-stream-consumer-${SUFFIX}"
   export ROLE_NAME="dva-ddb-stream-role-${SUFFIX}"
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   echo "$TABLE_NAME / $FUNCTION_NAME / $ROLE_NAME / $ACCOUNT_ID"
   ```

2. **Create the DynamoDB table with a stream enabled** — `PAY_PER_REQUEST` billing mode (the playground's allowed on-demand mode) and `StreamViewType=NEW_AND_OLD_IMAGES` so the stream carries both the item's state before and after each change, then wait for it to become `ACTIVE`:
   ```bash
   aws dynamodb create-table \
       --table-name "$TABLE_NAME" \
       --attribute-definitions AttributeName=OrderId,AttributeType=S \
       --key-schema AttributeName=OrderId,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST \
       --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES

   aws dynamodb wait table-exists --table-name "$TABLE_NAME"

   export STREAM_ARN=$(aws dynamodb describe-table \
       --table-name "$TABLE_NAME" \
       --query Table.LatestStreamArn --output text)
   echo "$STREAM_ARN"
   ```

3. **Create an execution role for the consumer Lambda**, then attach the AWS managed policy `AWSLambdaDynamoDBExecutionRole`, which grants exactly what a DynamoDB Streams-triggered function needs (`dynamodb:DescribeStream`, `dynamodb:GetRecords`, `dynamodb:GetShardIterator`, `dynamodb:ListStreams`, plus CloudWatch Logs writes):
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
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole
   ```
   > **Playground note:** the role is created under the `/service-role/` path — the same path the Lambda console uses for its auto-created roles. The playground allows `iam:PassRole` only for that path, so a role at the default `/` path would make `create-function` fail with `AccessDeniedException ... iam:PassRole`.

4. **Write and deploy the consumer Lambda function** — DynamoDB Streams records arrive as native DynamoDB JSON (each attribute tagged with its type, e.g. `{"S": "..."}`/`{"N": "..."}`), not base64 like Kinesis, and each record's `eventName` is `INSERT`, `MODIFY`, or `REMOVE`. The function reads `NewImage` (present on `INSERT`/`MODIFY`) or falls back to `OldImage` (present on `REMOVE`) and performs a small near-real-time transformation — computing an order total including tax:
   ```bash
   cat > lambda_function.py << 'EOF'
   def lambda_handler(event, context):
       transformed = 0
       for record in event["Records"]:
           event_name = record["eventName"]
           image = record["dynamodb"].get("NewImage") or record["dynamodb"].get("OldImage")
           order_id = image["OrderId"]["S"]
           if "AmountUsd" in image:
               amount = float(image["AmountUsd"]["N"])
               total_with_tax = round(amount * 1.08, 2)
               print(
                   f"Transformed record: eventName={event_name} order={order_id} "
                   f"amount={amount:.2f} total_with_tax={total_with_tax:.2f}"
               )
           else:
               print(f"Transformed record: eventName={event_name} order={order_id} (no amount)")
           transformed += 1
       return {"transformed": transformed}
   EOF
   zip function.zip lambda_function.py

   sleep 10  # allow the new IAM role to propagate before Lambda tries to assume it

   aws lambda create-function \
       --function-name "$FUNCTION_NAME" \
       --runtime python3.11 \
       --role "arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ROLE_NAME}" \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://function.zip \
       --timeout 10 \
       --memory-size 128

   aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME"
   ```

5. **Wire the stream to the function with an event source mapping** — this is the DynamoDB Streams trigger: Lambda polls the stream's shards on your behalf and invokes the function with a batch of records as soon as they're available. `--starting-position TRIM_HORIZON` means the function reads from the oldest available record in the stream, so it will pick up records regardless of exactly when they were produced relative to the mapping becoming active:
   ```bash
   export MAPPING_UUID=$(aws lambda create-event-source-mapping \
       --function-name "$FUNCTION_NAME" \
       --event-source-arn "$STREAM_ARN" \
       --starting-position TRIM_HORIZON \
       --batch-size 10 \
       --query UUID --output text)
   echo "$MAPPING_UUID"

   # Poll until the mapping is Enabled before writing items
   until [ "$(aws lambda get-event-source-mapping --uuid "$MAPPING_UUID" --query State --output text)" = "Enabled" ]; do
       echo "Waiting for event source mapping to become Enabled..."
       sleep 5
   done
   ```

6. **Generate INSERT, MODIFY, and REMOVE stream records** by writing to the table with `put-item`, `update-item`, and `delete-item` — each API call is itself a hands-on rep of the "write code that interacts with AWS services" skill, and each one produces a distinct stream record type the function must branch on:
   ```bash
   # INSERT
   aws dynamodb put-item \
       --table-name "$TABLE_NAME" \
       --item '{"OrderId": {"S": "order-1"}, "AmountUsd": {"N": "100"}}'

   aws dynamodb put-item \
       --table-name "$TABLE_NAME" \
       --item '{"OrderId": {"S": "order-2"}, "AmountUsd": {"N": "50"}}'

   # MODIFY
   aws dynamodb update-item \
       --table-name "$TABLE_NAME" \
       --key '{"OrderId": {"S": "order-1"}}' \
       --update-expression "SET AmountUsd = :amt" \
       --expression-attribute-values '{":amt": {"N": "125"}}'

   # REMOVE
   aws dynamodb delete-item \
       --table-name "$TABLE_NAME" \
       --key '{"OrderId": {"S": "order-2"}}'
   ```

7. **Give the event source mapping time to poll the stream and invoke**, then check the consumer's logs. DynamoDB Streams polling latency plus the Lambda cold start means the log group can take longer than a fixed short sleep to appear, and the 4 writes can land in CloudWatch Logs across more than one Lambda invocation a few seconds apart — so poll until all 4 `Transformed record` lines are visible (the same style of loop Step 5 used for the mapping to become `Enabled`), instead of guessing a single flat sleep or stopping at the first non-empty result:
   ```bash
   # Poll until at least 4 "Transformed record" lines have appeared (up to
   # ~75s), rather than stopping at the first non-empty result — the 4 writes
   # can be delivered across separate Lambda invocations/batches a few seconds
   # apart, so an early non-empty result can still be missing records. The
   # log group can also briefly not exist yet, which would otherwise surface
   # as a ResourceNotFoundException on the first check.
   for i in $(seq 1 15); do
       LOGS=$(aws logs filter-log-events \
           --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
           --query 'events[*].message' --output text 2>/dev/null)
       if [ "$(grep -c 'Transformed record' <<< "$LOGS")" -ge 4 ]; then
           break
       fi
       echo "Waiting for all 4 transformed-record log lines to appear..."
       sleep 5
   done
   echo "$LOGS"
   ```

## Validation

- `aws dynamodb describe-table --table-name "$TABLE_NAME" --query Table.StreamSpecification` returns `{"StreamEnabled": true, "StreamViewType": "NEW_AND_OLD_IMAGES"}`.
- `aws lambda get-event-source-mapping --uuid "$MAPPING_UUID" --query State --output text` returns `Enabled`.
- `aws logs filter-log-events --log-group-name "/aws/lambda/${FUNCTION_NAME}" --query 'events[*].message' --output text` shows four `Transformed record: eventName=...` lines (interleaved with Lambda's `INIT_START`/`START`/`END`/`REPORT` lines) — two `eventName=INSERT` lines (order-1 at $100, order-2 at $50), one `eventName=MODIFY` line (order-1 now $125, `total_with_tax=135.00`), and one `eventName=REMOVE` line (order-2) — proof the Lambda function consumed and transformed every change the table's stream delivered, in near real time and without any manual polling code in the lab itself.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
aws lambda delete-function --function-name "$FUNCTION_NAME"
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole
aws iam delete-role --role-name "$ROLE_NAME"
aws dynamodb delete-table --table-name "$TABLE_NAME"
rm -f trust-policy.json lambda_function.py function.zip
```
> **Playground note:** outside the playground you would first run `aws lambda delete-event-source-mapping --uuid "$MAPPING_UUID"`. The playground denies `lambda:DeleteEventSourceMapping`, so the mapping can't be removed here. Deleting the function and table does *not* remove it — `aws lambda list-event-source-mappings --function-name "$FUNCTION_NAME"` (before the function is gone) would still list it as `Enabled`. It is an inert orphan and the playground clears it when your session ends.

Confirm teardown:
```bash
aws dynamodb describe-table --table-name "$TABLE_NAME"    # should error: ResourceNotFoundException
aws lambda get-function --function-name "$FUNCTION_NAME"  # should error: ResourceNotFoundException
```

## References

- AWS CLI `dynamodb create-table` (`--stream-specification`, `StreamEnabled`/`StreamViewType`) — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/create-table.html
- AWS CLI `dynamodb wait table-exists` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/wait/table-exists.html
- AWS CLI `dynamodb describe-table` (`Table.LatestStreamArn`, `Table.StreamSpecification`) — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/describe-table.html
- AWS CLI `dynamodb put-item` / `update-item` / `delete-item` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/put-item.html, https://docs.aws.amazon.com/cli/latest/reference/dynamodb/update-item.html, https://docs.aws.amazon.com/cli/latest/reference/dynamodb/delete-item.html
- AWS Lambda Developer Guide, "Using AWS Lambda with Amazon DynamoDB" (event structure, `NewImage`/`OldImage`, `eventName`) — https://docs.aws.amazon.com/lambda/latest/dg/with-ddb.md
- AWS Lambda Developer Guide, "AWS managed policy: AWSLambdaDynamoDBExecutionRole" — https://docs.aws.amazon.com/lambda/latest/dg/security-iam-awsmanpol.md
- AWS CLI `lambda get-event-source-mapping` / `create-event-source-mapping` (`--starting-position TRIM_HORIZON`, valid for DynamoDB Streams and Kinesis) — https://docs.aws.amazon.com/cli/latest/reference/lambda/get-event-source-mapping.html, https://docs.aws.amazon.com/cli/latest/reference/lambda/create-event-source-mapping.html
- AWS CLI `lambda create-function`, `lambda wait function-active-v2` — https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html, https://docs.aws.amazon.com/cli/latest/reference/lambda/wait/function-active-v2.html
- AWS CLI `iam create-role` (`--path /service-role/`), `iam attach-role-policy` — https://docs.aws.amazon.com/cli/latest/reference/iam/create-role.html, https://docs.aws.amazon.com/cli/latest/reference/iam/attach-role-policy.html
- CloudWatch Logs `FilterLogEvents` API — https://github.com/aws/aws-cli/blob/develop/awscli/botocore/data/logs/2014-03-28/service-2.json
