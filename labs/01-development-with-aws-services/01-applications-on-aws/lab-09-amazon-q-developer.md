# Lab D1-T1-L09 — Accelerating Development with Amazon Q Developer

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.11` — Use Amazon Q Developer to assist with development

**Skills Practiced (secondary, cross-referenced):**
- `3.3.6` (see Domain 3 Task 3) — Use Amazon Q Developer to generate automated tests

**AWS Services Used:** Amazon Q Developer (delivered today as **Kiro CLI**, its officially rebranded successor — see note below), AWS Lambda, AWS Identity and Access Management (IAM)
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials; comes with the AWS CLI, Python 3, and `pip` preinstalled). A free **AWS Builder ID** — separate from your KodeKloud playground IAM credentials — which you can create in under a minute during Step 3 if you don't already have one; it costs nothing and needs no credit card. No resources from any other lab are used.

> **Naming note (read before you start):** in November 2025, AWS rebranded the standalone Amazon Q Developer command-line tool as **Kiro CLI** (binary `kiro-cli`); the old `amazon-q-developer-cli` project is archived. The DVA-C02 exam guide still names this capability "Amazon Q Developer" (skills 1.1.11, 3.3.6), and Amazon Q Developer continues to exist inside the AWS Management Console and other first-party surfaces, but the interactive command-line assistant you install and chat with — the tool that actually "assists with development" and "generates automated tests" at the terminal — is Kiro CLI. This lab uses it, since it is the current, officially supported, actually-installable implementation of the skills the exam is testing. Everything below is verified against AWS's own CloudShell and Kiro documentation, not assumed from older Amazon Q Developer CLI syntax.

**Playground Constraints to Respect:**
- Region: work in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1` (Kiro CLI sign-in and chat are region-agnostic; only the Lambda deployment step is region-scoped).
- CloudShell: "Basic operations are supported" per the playground doc — no dedicated Amazon Q Developer/Kiro allowance is documented, so this lab treats it like any other CLI tool installed into CloudShell's user-writable home directory (the same pattern `D1-T1-L07` uses for installing AWS SAM CLI via `pip3 install --user`).
- Kiro CLI installs to `~/.local/bin` with **no `sudo`/root required** — compatible with the playground's restricted IAM user.
- Kiro CLI's `--no-interactive` (headless/scripted) mode requires a paid `KIRO_API_KEY`; the free Builder ID tier only supports the normal **interactive** chat session used here — so every Q/Kiro prompt in this lab is typed into an interactive `kiro-cli chat` session, not scripted.
- Lambda: max 256 MB memory, max 10 s timeout, no container images.
- IAM: `iam:PutRolePolicy` (inline policies) is denied — this lab attaches the AWS managed policy `AWSLambdaBasicExecutionRole` instead. The Lambda execution role must be created under the `/service-role/` path or `iam:PassRole` fails.

## Purpose

Amazon Q Developer's job is to sit inside your terminal (or IDE) and turn natural-language requests into working code, explanations, and tests — without you leaving the command line. In this lab you sign in to the current Amazon Q Developer command-line experience (Kiro CLI) with a free AWS Builder ID, then use an interactive chat session to (1) generate a small Lambda handler from a plain-English description and (2) generate a pytest unit test suite for that handler — the two exam skills this lab covers. You then prove both artifacts actually work: you run the AI-generated tests locally, and you deploy the AI-generated handler to a real Lambda function and invoke it. The point isn't that the AI is infallible — it's that you can go from a natural-language request to reviewed, tested, deployed code in minutes, which is exactly what 1.1.11 and 3.3.6 test.

## Steps

1. **Open CloudShell and set shared variables:**
   ```bash
   export AWS_REGION=us-east-1
   export SUFFIX=$(date +%s)
   export FUNCTION_NAME="dva-q-dev-demo-${SUFFIX}"
   export ROLE_NAME="dva-q-dev-role-${SUFFIX}"
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   mkdir -p ~/q-dev-lab && cd ~/q-dev-lab
   echo "$FUNCTION_NAME / $ROLE_NAME / $ACCOUNT_ID"
   ```

2. **Install Kiro CLI (Amazon Q Developer's current CLI) into CloudShell** — it's a self-contained, non-root install into `~/.local/bin`, so it works under the playground's restricted IAM user:
   ```bash
   ldd --version | head -1   # confirm glibc >= 2.34; CloudShell's Amazon Linux base satisfies this
   which kiro-cli || {
     curl --proto '=https' --tlsv1.2 -sSf \
       'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
       -o kirocli.zip
     unzip -q -o kirocli.zip
     chmod +x kirocli/install.sh
     ./kirocli/install.sh
   }
   export PATH="$HOME/.local/bin:$PATH"
   kiro-cli --version
   ```
   If `ldd --version` reports glibc older than 2.34, use `kirocli-x86_64-linux-musl.zip` from the same base URL instead — the musl build has no external dependencies.

3. **Sign in with a free AWS Builder ID:**
   ```bash
   kiro-cli login
   ```
   Choose **"Use for Free with Builder ID"** when prompted. Kiro CLI prints a one-time code and a verification URL (`https://view.awsapps.com/start/#/device?user_code=XXXX-XXXX`) and polls in the background — this is the standard OAuth device-authorization flow (RFC 8628), the same pattern `aws sso login` uses. Open the URL in **your own browser** (any device), sign in with an existing Builder ID or create one on the spot (free, no credit card), and approve the request. If you don't select and copy the URL quickly, the CLI's progress spinner can overwrite it — hold your selection and press Ctrl+C to copy before it redraws. Back in CloudShell, the CLI confirms sign-in once you approve. Verify:
   ```bash
   kiro-cli whoami
   ```

4. **Ask Amazon Q Developer to write the Lambda handler** — start an interactive chat session:
   ```bash
   kiro-cli chat
   ```
   At the prompt, type (as plain text, one message):
   ```
   Write a single Python 3.12 AWS Lambda handler function named lambda_handler(event, context)
   in a file named lambda_function.py. It should read a JSON event with a key "numbers" (a list
   of numbers), and return a dict with statusCode 200 and a JSON-encoded body containing "sum"
   and "average" of that list. If the list is empty, return sum 0 and average 0 (avoid dividing
   by zero). Just show me the code in your reply — don't write any files or run any commands.
   ```
   Review the code Q/Kiro replies with. It should match this shape (your exact wording/formatting may differ — that's expected from a generative assistant; what matters is the same handler signature, input key, and output keys):
   ```python
   import json

   def lambda_handler(event, context):
       numbers = event.get("numbers", [])
       total = sum(numbers)
       average = total / len(numbers) if numbers else 0
       return {"statusCode": 200, "body": json.dumps({"sum": total, "average": average})}
   ```

5. **Ask it to generate automated tests for that handler (skill 3.3.6)** — in the same chat session, type:
   ```
   Now generate a pytest test file named test_lambda_function.py that imports lambda_handler from
   lambda_function and tests it with (a) a normal list of numbers and (b) an empty list. Just show
   me the code.
   ```
   Exit the chat session once you have both replies:
   ```
   /quit
   ```

6. **Save both AI-generated files** — paste the code Q/Kiro gave you (or the reference versions from Steps 4–5 if you want to move faster) into local files:
   ```bash
   cat > lambda_function.py << 'EOF'
   import json

   def lambda_handler(event, context):
       numbers = event.get("numbers", [])
       total = sum(numbers)
       average = total / len(numbers) if numbers else 0
       return {"statusCode": 200, "body": json.dumps({"sum": total, "average": average})}
   EOF

   cat > test_lambda_function.py << 'EOF'
   import json
   from lambda_function import lambda_handler

   def test_lambda_handler_with_numbers():
       result = lambda_handler({"numbers": [2, 4, 6]}, None)
       body = json.loads(result["body"])
       assert result["statusCode"] == 200
       assert body["sum"] == 12
       assert body["average"] == 4

   def test_lambda_handler_empty_list():
       result = lambda_handler({"numbers": []}, None)
       body = json.loads(result["body"])
       assert body["sum"] == 0
       assert body["average"] == 0
   EOF
   ```

7. **Run the AI-generated unit tests locally** — this is where 3.3.6 gets proven, not just demonstrated:
   ```bash
   python3 -m pip install --user pytest
   python3 -m pytest test_lambda_function.py -v
   ```

8. **Create the Lambda execution role** (managed policy only, `/service-role/` path — inline policies are denied in this playground):
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

9. **Deploy the AI-generated handler as a real Lambda function:**
   ```bash
   zip function.zip lambda_function.py
   sleep 10   # allow the new IAM role to propagate before Lambda tries to assume it

   aws lambda create-function \
       --function-name "$FUNCTION_NAME" \
       --runtime python3.12 \
       --role "arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ROLE_NAME}" \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://function.zip \
       --timeout 10 \
       --memory-size 256 \
       --region "$AWS_REGION"

   aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
   ```

10. **Invoke the deployed function** to confirm the Q/Kiro-generated code works in production, not just under pytest:
    ```bash
    aws lambda invoke \
        --cli-binary-format raw-in-base64-out \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --payload '{"numbers": [10, 20, 30]}' \
        response.json
    cat response.json
    ```

## Validation

- `kiro-cli whoami` (Step 3) confirms you're authenticated to Amazon Q Developer / Kiro CLI via AWS Builder ID.
- `python3 -m pytest test_lambda_function.py -v` (Step 7) shows both AI-generated tests passing — proof the generated test suite (skill 3.3.6) actually exercises and validates the generated handler.
- `cat response.json` (Step 10) shows `{"statusCode": 200, "body": "{\"sum\": 60, \"average\": 20.0}"}` (or equivalent), proving the AI-generated handler (skill 1.1.11) runs correctly as a real, deployed Lambda function.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

```bash
aws lambda delete-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
aws iam detach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$ROLE_NAME"
kiro-cli logout   # optional: signs your Builder ID out of this CloudShell session
cd ~ && rm -rf ~/q-dev-lab
```

Confirm teardown:
```bash
aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION"   # should error: ResourceNotFoundException
```

## References

- AWS CloudShell User Guide — "Using Kiro CLI in CloudShell" (sign-in flow, `kiro-cli`, `kiro-cli whoami`, `kiro-cli logout`) — https://docs.aws.amazon.com/cloudshell/latest/userguide/q-cli-features-in-cloudshell.html
- Kiro Docs — Linux installation (zip download, non-root `install.sh`, glibc/musl requirements) — https://kiro.dev/docs/getting-started/installation.md
- Kiro Docs — Authentication (Builder ID device-authorization flow, login method precedence) — https://kiro.dev/docs/getting-started/authentication.md
- Kiro Docs — Headless mode (confirms `--no-interactive` requires a paid `KIRO_API_KEY`, which is why this lab uses interactive chat) — https://kiro.dev/docs/cli/headless.md
- AWS DevOps & Developer Productivity Blog — "Amazon Q Developer end-of-support announcement" (rebrand/timeline context) — https://aws.amazon.com/blogs/devops/amazon-q-developer-end-of-support-announcement/
- AWS CLI `iam create-role` / `attach-role-policy` — https://docs.aws.amazon.com/cli/latest/reference/iam/create-role.html, https://docs.aws.amazon.com/cli/latest/reference/iam/attach-role-policy.html
- AWS CLI `lambda create-function` — https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html
- AWS CLI `lambda invoke` (`--cli-binary-format raw-in-base64-out`) — https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-options.md
- AWS CLI `lambda wait function-active-v2` — https://docs.aws.amazon.com/cli/latest/reference/lambda/wait/function-active-v2.html
