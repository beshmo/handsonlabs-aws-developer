# Lab D1-T2-L01 — Configuring Lambda: Environment Variables, Layers, and Triggers

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 2 — Develop code for AWS Lambda
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.2.2` — Configure Lambda functions by defining environment variables and parameters (for example, memory, concurrency, timeout, runtime, handler, layers, extensions, triggers, destinations)
- `1.2.5` — Integrate Lambda functions with AWS services

**Skills Practiced (secondary, cross-referenced):**
- None

**AWS Services Used:** AWS Lambda, Amazon S3, AWS Identity and Access Management (IAM), Amazon CloudWatch, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CLI configured against the KodeKloud playground credentials (for example AWS CloudShell, or a local shell with the `kk_labs_user_*` access keys); `zip` available; conceptual familiarity with Python and with what an S3 event notification is. No resources from any other lab are used.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- Lambda: max 256 MB memory, max 10 s timeout, max ~300 invocations/hour, no container images, layer usage is listed as permitted, but publishing layers (`lambda:PublishLayerVersion`) is denied for `kk_labs_user_*` identities, so this lab only attaches an existing AWS-published public layer and never creates one. Attaching a public layer ARN depends on the playground allowing `lambda:GetLayerVersion` on it; step 4 checks this before anything else depends on it. This lab uses 128 MB, a 10 s timeout, one public layer, and only a handful of invocations.
- S3: basic bucket and object operations only; bucket names are global, so the lab adds your account ID and a random suffix. One small bucket and two tiny objects.
- IAM: you can create a role and attach AWS managed policies, but inline role policies (`iam:PutRolePolicy`) are denied, so this lab attaches managed policies only. A role passed to Lambda must be created under `--path /service-role/` (`iam:PassRole` is denied at the default `/` path).
- CloudWatch Logs: reading logs works; `logs:DeleteLogGroup` is denied, so the function's log group remains until the session ends.

## Purpose

A Lambda function is more than code: its runtime behavior is shaped by configuration that lives outside the deployment package. In this lab you build one function and configure it three ways. An **environment variable** changes behavior without a redeploy, a **layer** supplies a shared library (the AWS-published Powertools for AWS Lambda layer) that is kept out of the function's own zip, and an **S3 event trigger** invokes the function whenever an object is uploaded. You then change the configuration and watch the behavior change, which is how the exam expects you to reason about handler, runtime, memory, timeout, layers, and triggers, and about integrating Lambda with another AWS service.

## Steps

1. **Set shared variables** — a random suffix and your account ID keep the globally unique bucket name and other names collision-free:
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$RANDOM
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export BUCKET_NAME="dva-uploads-${ACCOUNT_ID}-${SUFFIX}"
   export FUNCTION_NAME="dva-upload-processor-${SUFFIX}"
   export LAYER_ARN="arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV3-python312-x86_64:37"
   export ROLE_NAME="dva-upload-processor-role-${SUFFIX}"
   echo "$BUCKET_NAME / $FUNCTION_NAME / $ROLE_NAME"
   ```
   > *Optional:* in Windows Git Bash also run `export MSYS_NO_PATHCONV=1` so arguments with a leading slash (`--path /service-role/`, `--log-group-name /aws/lambda/...`) are not rewritten into Windows paths.

2. **Create the S3 bucket (the trigger source, skill 1.2.5)** — the function will react to uploads to this bucket. In `us-east-1` no `LocationConstraint` is passed:
   ```bash
   aws s3api create-bucket --bucket "$BUCKET_NAME" --region us-east-1
   ```

3. **Create the execution role (skill 1.2.5)** — the function needs to write logs and to read the uploaded object, so attach the AWS managed policies `AWSLambdaBasicExecutionRole` and `AmazonS3ReadOnlyAccess` (inline policies are denied in the playground, so a scoped inline policy is not an option here; in a real account you would scope S3 read access to this one bucket). Create the role under `/service-role/`:
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
       --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
   ```
   > **Playground note:** the `/service-role/` path is required because the playground allows `iam:PassRole` for Lambda only on that path; a role at `/` would make `create-function` fail with `AccessDeniedException ... iam:PassRole`.

4. **Look up an AWS-published public layer (skill 1.2.2: layers)** — a layer is a zip extracted under `/opt` in the execution environment; for Python, libraries sit under `/opt/python`, which is already on the import path. Publishing a layer is denied in the playground, so you attach an existing one: Powertools for AWS Lambda (Python), published by AWS in account `017000801446`. The ARN pattern is `arn:aws:lambda:<region>:017000801446:layer:AWSLambdaPowertoolsPythonV3-<python version>-<architecture>:<version>`, and a function must reference a layer by its full versioned ARN. `LAYER_ARN` (set in step 1) targets `python312` on `x86_64`, matching this lab's runtime and Lambda's default architecture. Confirm the layer is readable before building on it:
   ```bash
   aws lambda get-layer-version-by-arn --arn "$LAYER_ARN" \
       --query '{Arn:LayerVersionArn,Version:Version,Runtimes:CompatibleRuntimes}'
   ```
   > **If this fails:** an `AccessDeniedException` for `lambda:GetLayerVersion` means the playground does not allow attaching public layers, and the remainder of the layer part of this lab cannot work. If instead the version is reported as not found, AWS has retired that version; use a newer version number from the Powertools install documentation (see References) in `LAYER_ARN`.

5. **Write and deploy the function with an environment variable and the layer (skill 1.2.2)** — the handler is triggered by an S3 event, reads the new object, and logs a structured result with the layer's `Logger`. The number of preview lines comes from the `PREVIEW_LINES` environment variable, so changing it needs no code change. The code zip contains only the handler, not the Powertools library:
   ```bash
   cat > lambda_function.py << 'EOF'
   import os
   import urllib.parse

   import boto3
   from aws_lambda_powertools import Logger  # provided by the layer under /opt/python

   logger = Logger(service="upload-processor")
   s3 = boto3.client("s3")
   PREVIEW_LINES = int(os.environ.get("PREVIEW_LINES", "1"))
   STAGE = os.environ.get("STAGE", "unset")


   def lambda_handler(event, context):
       record = event["Records"][0]
       bucket = record["s3"]["bucket"]["name"]
       key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
       body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
       lines = body.splitlines()
       result = {
           "lines": len(lines),
           "words": len(body.split()),
           "preview": lines[:PREVIEW_LINES],
       }
       logger.info("PROCESSED", stage=STAGE, key=key, **result)
       return result
   EOF
   zip function.zip lambda_function.py

   sleep 10  # allow the new IAM role to propagate before Lambda tries to assume it

   aws lambda create-function \
       --function-name "$FUNCTION_NAME" \
       --runtime python3.12 \
       --role "arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ROLE_NAME}" \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://function.zip \
       --timeout 10 \
       --memory-size 128 \
       --layers "$LAYER_ARN" \
       --environment "Variables={STAGE=dev,PREVIEW_LINES=1}"

   aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME"
   export FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" \
       --query Configuration.FunctionArn --output text)
   echo "$FUNCTION_ARN"
   ```
   > Attaching the layer is one more parameter on the same call: `--layers` takes the full versioned ARN. Lambda checks at this point that your identity may read the layer version.

   `--handler` (`file.function`), `--runtime`, `--timeout`, `--memory-size`, `--layers` and `--environment` are exactly the configuration parameters skill 1.2.2 names.

6. **Allow S3 to invoke the function (skill 1.2.5)** — an S3 event notification is an asynchronous push, so Lambda's resource-based policy must allow the `s3.amazonaws.com` principal. `--source-arn` restricts it to this bucket and `--source-account` guards against a deleted-and-recreated bucket name owned by someone else:
   ```bash
   aws lambda add-permission \
       --function-name "$FUNCTION_NAME" \
       --statement-id allow-s3-upload-bucket \
       --action lambda:InvokeFunction \
       --principal s3.amazonaws.com \
       --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
       --source-account "$ACCOUNT_ID"
   ```

7. **Configure the S3 trigger (skills 1.2.2: triggers, 1.2.5)** — invoke the function for object creations whose key starts with `uploads/` and ends with `.txt`. S3 validates at this point that the function's permissions allow it, which is why step 6 comes first. The call replaces the bucket's whole notification configuration, which is fine on a new bucket:
   ```bash
   cat > notification.json << EOF
   {
     "LambdaFunctionConfigurations": [
       {
         "Id": "process-text-uploads",
         "LambdaFunctionArn": "${FUNCTION_ARN}",
         "Events": ["s3:ObjectCreated:*"],
         "Filter": {
           "Key": {
             "FilterRules": [
               {"Name": "prefix", "Value": "uploads/"},
               {"Name": "suffix", "Value": ".txt"}
             ]
           }
         }
       }
     ]
   }
   EOF
   aws s3api put-bucket-notification-configuration \
       --bucket "$BUCKET_NAME" \
       --notification-configuration file://notification.json
   ```
   The command prints nothing on success.

8. **Upload a matching and a non-matching object** — only `uploads/notes.txt` satisfies the prefix and suffix filters, so only it should invoke the function. Record a start time first so the log query only sees this run:
   ```bash
   export START_MS=$(( $(date +%s) * 1000 - 5000 ))

   printf 'first line\nsecond line\nthird line\n' > notes.txt
   aws s3api put-object --bucket "$BUCKET_NAME" --key uploads/notes.txt --body notes.txt
   aws s3api put-object --bucket "$BUCKET_NAME" --key uploads/ignored.csv --body notes.txt
   ```

9. **Read the function's logs** — delivery and log ingestion are asynchronous and the log group does not exist until the first invocation, so poll for up to two minutes. A `ResourceNotFoundException ... log group does not exist` message right after the upload is expected while the loop keeps retrying:
   ```bash
   for i in $(seq 1 12); do
     OUT=$(aws logs filter-log-events \
         --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
         --filter-pattern '"PROCESSED"' \
         --start-time "$START_MS" \
         --query 'events[*].message' --output text)
     [ -n "$OUT" ] && break
     echo "no log lines yet, waiting..."; sleep 10
   done
   echo "$OUT"
   ```
   You should see one JSON log line (written by the layer's `Logger`) with `"message": "PROCESSED"`, `"stage": "dev"`, `"key": "uploads/notes.txt"`, `"lines": 3`, `"words": 6`, and a `preview` list with **one** entry (`PREVIEW_LINES=1`). The `.csv` upload produced no line.

10. **Change behavior by changing configuration only (skill 1.2.2)** — update the environment variables without touching the code, then upload again. Note that `--environment` replaces the whole variable map, so every variable you want to keep must be restated:
    ```bash
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "Variables={STAGE=test,PREVIEW_LINES=3}"
    aws lambda wait function-updated-v2 --function-name "$FUNCTION_NAME"

    export START_MS=$(( $(date +%s) * 1000 - 5000 ))
    aws s3api put-object --bucket "$BUCKET_NAME" --key uploads/notes2.txt --body notes.txt

    for i in $(seq 1 12); do
      OUT=$(aws logs filter-log-events \
          --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
          --filter-pattern '"PROCESSED"' \
          --start-time "$START_MS" \
          --query 'events[*].message' --output text)
      [ -n "$OUT" ] && break
      echo "no log lines yet, waiting..."; sleep 10
    done
    echo "$OUT"
    ```
    The new line shows `"stage": "test"` and a `preview` with three entries, with the same code and the same layer.

11. **Inspect the final configuration** — confirm every setting from one place:
    ```bash
    aws lambda get-function-configuration --function-name "$FUNCTION_NAME" \
        --query '{Runtime:Runtime,Handler:Handler,Memory:MemorySize,Timeout:Timeout,Layers:Layers[*].Arn,Env:Environment.Variables}'
    aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" \
        --query 'LambdaFunctionConfigurations[*].{Id:Id,Events:Events,Arn:LambdaFunctionArn}'
    ```

## Validation

- `get-function-configuration` shows `Runtime` `python3.12`, `Handler` `lambda_function.lambda_handler`, `Memory` 128, `Timeout` 10, the public layer ARN (`...:layer:AWSLambdaPowertoolsPythonV3-python312-x86_64:37`) under `Layers`, and `Env` of `STAGE=test`, `PREVIEW_LINES=3`.
- `get-bucket-notification-configuration` lists the `process-text-uploads` configuration pointing at the function ARN for `s3:ObjectCreated:*`.
- The step 9 log query returned exactly one `PROCESSED` line (for `uploads/notes.txt`, `"stage": "dev"`, one-entry preview), and none for `uploads/ignored.csv`: the prefix/suffix filter worked. The step 10 line shows `"stage": "test"` with a three-entry preview: configuration changed behavior with no code change. The successful `from aws_lambda_powertools import Logger` (the library is not in `function.zip`) and the JSON-formatted log line prove the layer is mounted at `/opt/python`.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
# 1. Remove the trigger, then empty and delete the bucket
aws s3api put-bucket-notification-configuration --bucket "$BUCKET_NAME" --notification-configuration '{}'
aws s3 rb "s3://${BUCKET_NAME}" --force

# 2. Delete the function (this also removes its resource-based policy)
aws lambda delete-function --function-name "$FUNCTION_NAME"

# 3. Detach the managed policies, then delete the role
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam delete-role --role-name "$ROLE_NAME"

rm -rf function.zip lambda_function.py trust-policy.json notification.json notes.txt
```

The function's CloudWatch Logs group (`/aws/lambda/<function name>`) is left behind by Lambda. The playground denies `logs:DeleteLogGroup`, so it simply remains until your session ends.

## References

- AWS CLI `lambda get-layer-version-by-arn` — https://docs.aws.amazon.com/cli/latest/reference/lambda/get-layer-version-by-arn.html
- Powertools for AWS Lambda (Python): Lambda layer ARNs — https://docs.powertools.aws.dev/lambda/python/latest/getting-started/install/
- AWS CLI `lambda create-function` (`--layers`, `--environment`) — https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html
- AWS CLI `lambda update-function-configuration` — https://docs.aws.amazon.com/cli/latest/reference/lambda/update-function-configuration.html
- AWS CLI `lambda add-permission` — https://docs.aws.amazon.com/cli/latest/reference/lambda/add-permission.html
- AWS CLI `s3api put-bucket-notification-configuration` — https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-notification-configuration.html
- AWS CLI `logs filter-log-events` — https://docs.aws.amazon.com/cli/latest/reference/logs/filter-log-events.html
- Lambda Developer Guide: layers and environment variables — https://docs.aws.amazon.com/lambda/latest/dg/chapter-layers.html, https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html
