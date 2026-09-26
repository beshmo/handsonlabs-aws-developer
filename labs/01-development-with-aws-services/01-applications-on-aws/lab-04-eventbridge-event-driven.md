# Lab D1-T1-L04 — Event-Driven Architecture with Amazon EventBridge

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.12` — Use Amazon EventBridge to implement event-driven patterns
- `1.1.1` — Describe architectural patterns (for example, event-driven, microservices, monolithic, choreography, orchestration, fanout)

**Skills Practiced (secondary, cross-referenced):**
- None

**AWS Services Used:** Amazon EventBridge, Amazon S3, AWS Lambda, AWS Identity and Access Management (IAM), Amazon CloudWatch, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials). Conceptual familiarity with JSON and with what an AWS Lambda function is. No resources from any other lab are used.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- EventBridge: the playground denies `events:CreateEventBus` and `events:PutEvents` (on every bus), so you cannot create a custom bus or publish your own events. This lab uses only the account's `default` bus and lets Amazon S3 be the event producer. `events:PutRule`, `events:PutTargets` (Lambda target), `events:TestEventPattern` and `lambda:AddPermission` for `events.amazonaws.com` work on the `default` bus.
- S3: basic bucket and object operations only; bucket names are global, so the lab adds your account ID and a random suffix. One small bucket and two tiny objects.
- Lambda: max 256 MB memory, max 10 s timeout, no container images, max ~300 invocations/hour — this lab uses 128 MB, a 10 s timeout, and one invocation.
- IAM: you can create a role and attach AWS managed policies to it, but inline role policies (`iam:PutRolePolicy`) are denied — so this lab attaches a managed policy instead. Lambda can only use a role you create under the `/service-role/` path (`iam:PassRole` is denied on roles at the default `/` path).
- CloudWatch Logs: reading logs works; `logs:DeleteLogGroup` is denied, so the function's log group remains until the session ends.

## Purpose

In an event-driven architecture, a producer announces that something happened without knowing who, if anyone, will react; consumers subscribe by declaring the kind of event they care about, and the routing lives in the event bus rather than in producer code. In this lab Amazon S3 is the producer: with EventBridge notifications turned on, every object upload becomes an `Object Created` event on the `default` event bus. You write a rule whose event pattern filters on the event's content (source, detail type, bucket name and an object-key prefix), point it at a Lambda function, and then upload one object that matches and one that does not. Only the matching event reaches the consumer, which is the loosely coupled, rule-based routing the exam expects you to describe and implement.

## Steps

1. **Open CloudShell and set shared variables** — a random suffix and your account ID keep the globally unique bucket name and the other names collision-free:
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$RANDOM
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export BUCKET_NAME="dva-orders-${ACCOUNT_ID}-${SUFFIX}"
   export FUNCTION_NAME="dva-order-handler-${SUFFIX}"
   export ROLE_NAME="dva-order-handler-role-${SUFFIX}"
   export RULE_NAME="dva-new-order-uploads"
   echo "$BUCKET_NAME / $FUNCTION_NAME / $ROLE_NAME"
   ```
   > *Optional:* if you run these commands in Windows Git Bash instead of CloudShell, also run `export MSYS_NO_PATHCONV=1` once here so arguments with a leading slash (`--path /service-role/`, `--log-group-name /aws/lambda/...`) are not rewritten into Windows paths.

2. **Create the S3 bucket and turn on Amazon EventBridge notifications (the event producer — skills 1.1.12, 1.1.1)** — S3 sends nothing to EventBridge by default; setting `EventBridgeConfiguration` on the bucket makes S3 publish its object events (such as `Object Created`) to the `default` event bus of the same account and Region. Note that `put-bucket-notification-configuration` replaces the bucket's whole notification configuration, which is fine on a brand-new bucket. In `us-east-1` no `LocationConstraint` is passed:
   ```bash
   aws s3api create-bucket --bucket "$BUCKET_NAME" --region us-east-1

   aws s3api put-bucket-notification-configuration \
       --bucket "$BUCKET_NAME" \
       --notification-configuration '{"EventBridgeConfiguration": {}}'
   ```
   The second command prints nothing on success. Enabling delivery can take a short while to become effective, so the lab waits before the first upload (step 9).

3. **Create an execution role for the consumer Lambda** — the consumer only needs to write its own logs, so attach the AWS managed policy `AWSLambdaBasicExecutionRole`. Create the role under `/service-role/` (see the playground note below):
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
   ```
   > **Playground note:** the role is created under the `/service-role/` path — the same path the Lambda console uses for its auto-created roles. The playground allows `iam:PassRole` only for that path, so a role at the default `/` path would make `create-function` fail with `AccessDeniedException ... iam:PassRole`. In real accounts the path is just an organizational label. Inline policies are denied, which is why a managed policy is attached here.
   >

4. **Write and deploy the consumer Lambda function** — it receives the full EventBridge event envelope as its input and logs it; it has no idea who produced the event or which rule matched it:
   ```bash
   cat > lambda_function.py << 'EOF'
   import json

   def lambda_handler(event, context):
       print("Received event: " + json.dumps(event))
       return {
           "source": event["source"],
           "detail-type": event["detail-type"],
           "key": event["detail"]["object"]["key"],
       }
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

   aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME"   # returns once State is Active
   export FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" \
       --query Configuration.FunctionArn --output text)
   echo "$FUNCTION_ARN"
   ```

5. **Define the event pattern and test it without sending anything (skill 1.1.12)** — an event pattern is a JSON template that an event must match field by field. This one requires the S3 source, the `Object Created` detail type, your bucket, and an object key that starts with `orders/` (the `prefix` operator). `test-event-pattern` evaluates a pattern against a sample event and returns `true` or `false`, a fast way to debug a pattern before wiring a target. The sample events below carry the fields `test-event-pattern` requires (`id`, `account`, `region`, `time`, `source`, `detail-type`, `detail`):
   ```bash
   cat > pattern.json << EOF
   {
     "source": ["aws.s3"],
     "detail-type": ["Object Created"],
     "detail": {
       "bucket": {"name": ["${BUCKET_NAME}"]},
       "object": {"key": [{"prefix": "orders/"}]}
     }
   }
   EOF

   # Sample event 1: key under orders/  (should match)
   aws events test-event-pattern --event-pattern file://pattern.json --event \
     "{\"id\":\"1\",\"account\":\"${ACCOUNT_ID}\",\"region\":\"us-east-1\",\"time\":\"2024-01-01T00:00:00Z\",\"source\":\"aws.s3\",\"detail-type\":\"Object Created\",\"detail\":{\"bucket\":{\"name\":\"${BUCKET_NAME}\"},\"object\":{\"key\":\"orders/order-1001.json\"}}}"

   # Sample event 2: key under archive/  (should not match)
   aws events test-event-pattern --event-pattern file://pattern.json --event \
     "{\"id\":\"2\",\"account\":\"${ACCOUNT_ID}\",\"region\":\"us-east-1\",\"time\":\"2024-01-01T00:00:00Z\",\"source\":\"aws.s3\",\"detail-type\":\"Object Created\",\"detail\":{\"bucket\":{\"name\":\"${BUCKET_NAME}\"},\"object\":{\"key\":\"archive/order-1002.json\"}}}"
   ```
   The first call returns `"Result": true`; the second returns `"Result": false`.

6. **Create the rule on the `default` event bus (skills 1.1.12, 1.1.1)** — a rule is one independent subscription: it owns the pattern, and the producer never references it. Rules see only events sent to the bus they belong to, and AWS service events such as S3's arrive on `default`:
   ```bash
   export RULE_ARN=$(aws events put-rule \
       --name "$RULE_NAME" \
       --event-bus-name default \
       --event-pattern file://pattern.json \
       --query RuleArn --output text)
   echo "$RULE_ARN"
   ```
   The `put-rule` output is the rule ARN, of the form `arn:aws:events:us-east-1:<account>:rule/<rule-name>` for a rule on the default bus.

7. **Let EventBridge invoke the function** — Lambda's resource-based policy must explicitly allow the `events.amazonaws.com` principal, scoped to this rule's ARN with `--source-arn` so no other rule can invoke the function:
   ```bash
   aws lambda add-permission \
       --function-name "$FUNCTION_NAME" \
       --statement-id allow-rule-new-order-uploads \
       --action lambda:InvokeFunction \
       --principal events.amazonaws.com \
       --source-arn "$RULE_ARN"
   ```

8. **Attach the function as the rule's target** — a target is where a matching event is delivered:
   ```bash
   aws events put-targets --rule "$RULE_NAME" --event-bus-name default \
       --targets "Id"="order-handler","Arn"="$FUNCTION_ARN"
   ```
   The call should report `"FailedEntryCount": 0`.

9. **Act as the producer: upload one matching and one non-matching object** — you never call EventBridge; you just use S3. `orders/order-1001.json` matches the rule's prefix filter and `archive/order-1002.json` does not. Record a start time first so the log query only looks at this run, and pause briefly so the bucket notification setting and the new rule are active:
   ```bash
   sleep 30
   export START_MS=$(( $(date +%s) * 1000 - 5000 ))

   echo '{"orderId":"1001","amount":250}' > order-1001.json
   echo '{"orderId":"1002","amount":40}'  > order-1002.json

   aws s3api put-object --bucket "$BUCKET_NAME" --key orders/order-1001.json  --body order-1001.json
   aws s3api put-object --bucket "$BUCKET_NAME" --key archive/order-1002.json --body order-1002.json
   ```
   Each upload is a fire-and-forget hand-off: S3 emits an `Object Created` event for both objects, and EventBridge decides which of them the rule forwards.

10. **Read the consumer's logs** — delivery to Lambda and log ingestion are asynchronous, and the log group does not exist until the first invocation, so poll for up to two minutes. Right after the upload, a `ResourceNotFoundException ... The specified log group does not exist` message is expected while the function has not run yet and the loop keeps retrying; any other error message is a real problem to fix:
    ```bash
    for i in $(seq 1 12); do
      OUT=$(aws logs filter-log-events \
          --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
          --filter-pattern '"Received event"' \
          --start-time "$START_MS" \
          --query 'events[*].message' --output text)
      [ -n "$OUT" ] && break
      echo "no log lines yet, waiting..."; sleep 10
    done
    echo "$OUT"
    ```
    You should see one `Received event:` line whose `detail.object.key` is `orders/order-1001.json`. Wait about 20 more seconds and run the `filter-log-events` command once more to confirm that no second line (for `archive/order-1002.json`) has appeared.

11. **Map what you built to the architectural pattern (skill 1.1.1)** — answer for yourself, then check against the answers:
    - *Who is the producer, the router and the consumer?* S3 (producer), the EventBridge `default` bus plus your rule (router), the Lambda function (consumer).
    - *What does the producer know about the consumer?* Nothing: S3 only has EventBridge notifications switched on. That loose coupling is what makes the design event-driven, and because each service reacts to events on its own with no central coordinator, it is choreography rather than orchestration.
    - *How would you add a second consumer, for example an SQS queue or another Lambda function?* Add another rule (or another target on the same rule) with `put-targets`. The bucket and the existing function do not change; this many-consumers-per-event shape is the same idea as fanout.

## Validation

- `test-event-pattern` returned `"Result": true` for the `orders/order-1001.json` sample and `"Result": false` for the `archive/order-1002.json` sample — the content filter in the rule's pattern behaves as designed.
- `aws events put-targets` reported `"FailedEntryCount": 0`, and `aws events list-targets-by-rule --rule "$RULE_NAME" --event-bus-name default --query 'Targets[*].Arn' --output text` prints the function ARN.
- The log query shows exactly **one** `Received event:` line, with `"source": "aws.s3"`, `"detail-type": "Object Created"`, your bucket name, and `"key": "orders/order-1001.json"`. The `archive/order-1002.json` upload does **not** appear: S3 published the event to the bus, but no rule matched it, so nothing was delivered.
- Optional (CloudWatch metrics can lag by several minutes): the function's `Invocations` metric sums to 1:
  ```bash
  aws cloudwatch get-metric-statistics \
      --namespace AWS/Lambda --metric-name Invocations \
      --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
      --start-time "$(date -u -d '-30 minutes' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 300 --statistics Sum \
      --query 'Datapoints[*].Sum' --output text
  ```

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
# 1. Targets must be removed before their rule
aws events remove-targets --rule "$RULE_NAME" --event-bus-name default --ids order-handler
aws events delete-rule --name "$RULE_NAME" --event-bus-name default

# 2. Lambda function (this also removes its resource-based policy)
aws lambda delete-function --function-name "$FUNCTION_NAME"

# 3. Detach the managed policy, then delete the role
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$ROLE_NAME"

# 4. Empty and delete the bucket (its EventBridge notification setting is deleted with it)
aws s3 rb "s3://${BUCKET_NAME}" --force

rm -f trust-policy.json lambda_function.py function.zip pattern.json order-1001.json order-1002.json
```

The function's CloudWatch Logs group (`/aws/lambda/<function name>`) is left behind by Lambda. The playground denies `logs:DeleteLogGroup`, so it simply remains until your session ends.

## References

- AWS CLI `s3api put-bucket-notification-configuration` (`EventBridgeConfiguration`) — https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-notification-configuration.html
- AWS CLI `s3api create-bucket` — https://docs.aws.amazon.com/cli/latest/reference/s3api/create-bucket.html
- AWS CLI `s3api put-object` — https://docs.aws.amazon.com/cli/latest/reference/s3api/put-object.html
- AWS CLI `s3 rb` — https://docs.aws.amazon.com/cli/latest/reference/s3/rb.html
- EventBridge: tutorial, send an email when S3 events happen (event pattern for `aws.s3` / `Object Created`, rule on the default bus) — https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-s3-object-created-tutorial.html
- AWS CLI `events put-rule` / `delete-rule` — https://docs.aws.amazon.com/cli/latest/reference/events/put-rule.html, https://docs.aws.amazon.com/cli/latest/reference/events/delete-rule.html
- AWS CLI `events put-targets` / `remove-targets` — https://docs.aws.amazon.com/cli/latest/reference/events/put-targets.html, https://docs.aws.amazon.com/cli/latest/reference/events/remove-targets.html
- AWS CLI `events test-event-pattern` — https://docs.aws.amazon.com/cli/latest/reference/events/test-event-pattern.html
- EventBridge comparison operators in event patterns (`prefix` matching) — https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern-operators.html
- EventBridge resource-based policy for invoking a Lambda target — https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html
- AWS CLI `lambda add-permission` — https://docs.aws.amazon.com/cli/latest/reference/lambda/add-permission.html
- AWS CLI `lambda create-function` — https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html
- AWS CLI `logs filter-log-events` — https://docs.aws.amazon.com/cli/latest/reference/logs/filter-log-events.html
- AWS CLI `cloudwatch get-metric-statistics` — https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/get-metric-statistics.html
- AWS CLI `iam attach-role-policy` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/iam/attach-role-policy.rst
