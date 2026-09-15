# Lab D1-T1-L01 — AWS SDK & CLI Fundamentals: Making Authenticated Calls

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.9` — Write code that interacts with AWS services by using APIs and AWS SDKs

**Skills Practiced (secondary, cross-referenced):**
- `2.1.3` (see Domain 2 Task 1) — Configure programmatic access to AWS
- `2.1.4` (see Domain 2 Task 1) — Make authenticated calls to AWS services

**AWS Services Used:** AWS CloudShell, AWS Identity and Access Management (IAM), AWS Security Token Service (AWS STS), Amazon S3, Amazon DynamoDB, AWS CLI, AWS SDK for Python (Boto3)
**Region:** us-east-1
**Prerequisites:** A KodeKloud AWS Playground session (no local machine setup needed — this lab runs entirely in AWS CloudShell, which comes pre-authenticated with the playground's IAM credentials and Python 3 + Boto3 preinstalled). Basic familiarity with Python and JSON.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- S3 buckets must use standard (server-side) encryption and keep bucket policies minimal.
- DynamoDB tables must use `PAY_PER_REQUEST` billing (or 1 RCU / 1 WCU provisioned) and cannot be global tables.
- CloudShell: basic operations only, no special configuration needed for this lab.

## Purpose

Every exam skill and every later lab in this course assumes you're comfortable making authenticated, programmatic calls to AWS — the exam tests this directly (SDK usage, programmatic access, authenticated calls). In this lab you'll use AWS CloudShell as a zero-setup terminal, confirm *who* you're authenticated as with STS, then write a short Boto3 (Python SDK) script that creates real resources (an S3 bucket and a DynamoDB table), writes and reads data through the SDK, and cross-checks the same data with equivalent AWS CLI commands — making the CLI-vs-SDK relationship concrete before you rely on both throughout the rest of the course.

## Steps

1. **Open AWS CloudShell and confirm your identity** — In the AWS Console, launch CloudShell (top nav bar icon). CloudShell already has your playground session's credentials configured, so there's nothing to set up. Run:
   ```bash
   aws sts get-caller-identity
   ```
   This proves you're making an *authenticated call* (skill 2.1.4) and shows the `Account`, `UserId`, and `Arn` your subsequent CLI/SDK calls will run as.

2. **Set shared variables for this session** — Every resource name must be unique, so generate a random suffix once and reuse it:
   ```bash
   export SUFFIX=$(date +%s)
   export BUCKET_NAME="dva-sdk-demo-${SUFFIX}"
   export TABLE_NAME="dva-sdk-demo-${SUFFIX}"
   echo "$BUCKET_NAME / $TABLE_NAME"
   ```

3. **Write a Boto3 script that talks to AWS entirely through the SDK** — Create `sdk_demo.py` in CloudShell (use the built-in code editor via the CloudShell "Actions" menu, or `cat > sdk_demo.py << 'EOF' ... EOF`):
   ```python
   import os
   import boto3

   bucket_name = os.environ["BUCKET_NAME"]
   table_name = os.environ["TABLE_NAME"]
   region = "us-east-1"

   session = boto3.session.Session()
   s3 = session.client("s3")
   dynamodb = session.resource("dynamodb")

   # 1) Create an S3 bucket with default (SSE-S3) encryption
   s3.create_bucket(Bucket=bucket_name)
   s3.put_bucket_encryption(
       Bucket=bucket_name,
       ServerSideEncryptionConfiguration={
           "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
       },
   )
   print(f"Created encrypted bucket: {bucket_name}")

   # 2) Upload an object using the SDK (not the CLI)
   s3.put_object(
       Bucket=bucket_name,
       Key="hello.json",
       Body=b'{"message": "written by boto3"}',
       ContentType="application/json",
   )
   print("Uploaded hello.json via put_object")

   # 3) Create a DynamoDB table in on-demand (PAY_PER_REQUEST) mode
   table = dynamodb.create_table(
       TableName=table_name,
       KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
       AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}],
       BillingMode="PAY_PER_REQUEST",
   )
   table.wait_until_exists()
   print(f"Table {table_name} is ACTIVE")

   # 4) Write and read an item using the SDK
   table.put_item(Item={"pk": "demo-item", "source": "boto3", "count": 1})
   response = table.get_item(Key={"pk": "demo-item"})
   print("Item read back via SDK:", response["Item"])
   ```

4. **Run the script** — Skill 1.1.9 in action: every AWS interaction above happened through the SDK's client/resource objects, not raw HTTP or the CLI.
   ```bash
   python3 sdk_demo.py
   ```
   You should see the bucket creation, upload, table-active, and item-read-back messages print in order.

5. **Cross-check the same data with the AWS CLI** — This shows that the CLI and SDK are two clients for the same authenticated session and the same underlying AWS APIs (skill 2.1.3 — programmatic access is configured once, used by both tools):
   ```bash
   aws s3 cp s3://$BUCKET_NAME/hello.json - 
   aws dynamodb get-item --table-name "$TABLE_NAME" --key '{"pk": {"S": "demo-item"}}'
   ```
   The CLI output should match exactly what the Python script wrote.

## Validation

- `aws sts get-caller-identity` returned an `Arn` for your playground session (confirms authenticated access before you did anything else).
- The Python script printed all four steps without errors, ending with `Item read back via SDK: {'pk': 'demo-item', 'source': 'boto3', 'count': Decimal('1')}`.
- `aws s3 cp s3://$BUCKET_NAME/hello.json -` prints `{"message": "written by boto3"}`.
- `aws dynamodb get-item --table-name "$TABLE_NAME" --key '{"pk": {"S": "demo-item"}}'` returns the same item the SDK wrote.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

Run these in the same CloudShell session (variables are still set):
```bash
aws dynamodb delete-table --table-name "$TABLE_NAME"
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME
rm -f sdk_demo.py
```
Confirm the table and bucket are gone:
```bash
aws dynamodb describe-table --table-name "$TABLE_NAME"   # should error: ResourceNotFoundException
aws s3 ls s3://$BUCKET_NAME                                # should error: NoSuchBucket
```

## References

- AWS CLI `sts get-caller-identity` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/sts/get-caller-identity.rst
- AWS CLI `dynamodb create-table` (on-demand mode) — https://github.com/aws/aws-cli/blob/develop/awscli/examples/dynamodb/create-table.rst
- AWS CLI `dynamodb get-item` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/dynamodb/get-item.rst
- AWS CLI `s3 cp` — https://github.com/aws/aws-cli/blob/develop/awscli/examples/s3/cp.rst
- AWS CLI `s3 rb` (force delete bucket) — https://github.com/aws/aws-cli/blob/develop/awscli/examples/s3/rb.rst
- Boto3 DynamoDB Table `put_item` / `get_item` guide — https://github.com/boto/boto3/blob/develop/docs/source/guide/dynamodb.rst
- Boto3 Session and client/resource creation — https://github.com/boto/boto3/blob/develop/docs/source/guide/session.rst
