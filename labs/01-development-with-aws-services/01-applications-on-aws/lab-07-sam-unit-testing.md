# Lab D1-T1-L07 — Unit Testing Serverless Apps with AWS SAM

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.7` — Write and run unit tests in development environments (for example, using AWS SAM)

**Skills Practiced (secondary, cross-referenced):**
- `3.3.1` (see Domain 3 Task 3) — Create application test events (for example, JSON payloads for testing AWS Lambda, API Gateway, AWS SAM resources)

**AWS Services Used:** AWS SAM, AWS Lambda
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials; comes with the AWS CLI, Python 3, and `pip` preinstalled) — this lab installs the AWS SAM CLI into it. Conceptual familiarity with a basic Lambda handler signature (`event`, `context`). No resources from any other lab are used, and this lab makes **no live AWS API calls** — skill 1.1.7 is specifically about testing "in development environments," so everything here runs against your local SAM project directory, not a deployed function. Because `sam build` (without `--use-container`, which needs Docker and is unavailable in this playground) validates that the *local* `python3` on `PATH` matches the SAM runtime's major.minor version, this lab detects your CloudShell session's exact `python3` version at Step 2 and passes that value to `sam init --runtime`, instead of hardcoding one.
**Playground Constraints to Respect:**
- Lambda: max 256 MB memory, max 10 second timeout, no container images — the lab's `template.yaml` sets `MemorySize: 256` / `Timeout: 10` in `Globals` so the function stays deploy-ready for later labs (e.g. D1-T2-L04, D3-T3-L04) even though it is never deployed here; the build uses the default Zip package type, never `--use-container` (which needs Docker).
- Region: `us-east-1` — nominal only, since no resources are created in any region during this lab.
- IAM: not applicable — no roles are created because nothing is deployed.

## Purpose

AWS SAM scaffolds every new serverless project with a `tests/unit/` folder specifically so you can validate Lambda handler logic without waiting on a deployment — this is what skill 1.1.7 means by "unit tests in development environments." In this lab you initialize a SAM application, run its baseline unit tests locally with `pytest`, then practice a short test-driven cycle: you generate a realistic API Gateway test event with `sam local generate-event` (skill 3.3.1 — creating application test events), write a new test against a feature that doesn't exist yet and watch it fail (red), implement the feature in the handler, and watch the same test pass (green). You finish by running `sam build` to confirm the tested code still packages cleanly as a deployable artifact. Every step happens on disk in your CloudShell session — no Lambda function, API, or IAM role is ever created in the AWS account.

## Steps

1. **Install the AWS SAM CLI** — CloudShell doesn't ship with it preinstalled, so install it into your user site-packages and confirm the version:
   ```bash
   pip3 install --user aws-sam-cli
   export PATH="$HOME/.local/bin:$PATH"
   sam --version
   ```

2. **Detect the local Python version and derive the matching SAM runtime** — `sam build` (Step 11) runs without `--use-container` (no Docker in this playground), so it validates the handler against whatever `python3` is on `PATH` and fails outright if that doesn't match the runtime declared in `template.yaml`. Rather than hardcoding a runtime, capture CloudShell's actual `python3` major.minor version now and reuse it in the next step:
   ```bash
   PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
   PYTHON_RUNTIME="python$(echo "$PYTHON_VERSION" | cut -d. -f1,2)"
   echo "Local python3 is ${PYTHON_VERSION} -> using SAM runtime ${PYTHON_RUNTIME}"
   ```
   `PYTHON_RUNTIME` must be one of SAM CLI's supported `--runtime` values (at the time of writing: `python3.8` through `python3.14`); CloudShell's preinstalled Python 3 falls within this range.

3. **Scaffold a new SAM application non-interactively** — `sam init` generates the standard project layout (`template.yaml`, a handler module, an `events/` folder, and a `tests/unit/` folder) that every SAM-based unit-testing workflow builds on. Pass the runtime detected in the previous step instead of a hardcoded version, so the local-interpreter check in `sam build` is guaranteed to match:
   ```bash
   sam init --no-interactive \
       --name sam-unit-testing \
       --runtime "$PYTHON_RUNTIME" \
       --dependency-manager pip \
       --app-template hello-world

   cd sam-unit-testing
   find . -not -path '*/.aws-sam/*' -type f | sort
   ```

4. **Inspect the generated template** — confirm the function's runtime and see where you'll cap memory/timeout in the next step:
   ```bash
   cat template.yaml
   ```

5. **Cap memory and timeout inside the playground's Lambda ceiling** — edit `template.yaml` so the `Globals` section reads:
   ```yaml
   Globals:
     Function:
       Timeout: 10
       MemorySize: 256
   ```
   This keeps the function within the playground's 256 MB / 10 s Lambda limits, even though it's never deployed in this lab — the same template can be reused as-is in a later deployment lab.

6. **Replace the handler with a minimal, deterministic baseline** — the default `hello-world` handler makes an outbound HTTP call, which is unnecessary I/O for a unit-testing exercise. Overwrite `hello_world/app.py` with a self-contained handler:
   ```bash
   cat > hello_world/app.py << 'EOF'
   import json


   def lambda_handler(event, context):
       """Return a greeting. Defaults to 'World' when no name is supplied."""
       return {
           "statusCode": 200,
           "body": json.dumps({"message": "Hello, World!"}),
       }
   EOF
   ```

7. **Replace the generated test with a baseline unit test and run it** — this is the core of skill 1.1.7: exercising handler code directly with `pytest`, no deployment involved:
   ```bash
   python3 -m pip install --user pytest

   cat > tests/unit/test_handler.py << 'EOF'
   import json

   from hello_world import app


   def test_lambda_handler_returns_default_greeting():
       event = {"queryStringParameters": None}

       response = app.lambda_handler(event, {})
       body = json.loads(response["body"])

       assert response["statusCode"] == 200
       assert body["message"] == "Hello, World!"
   EOF

   python3 -m pytest tests/unit -v
   ```
   You should see `1 passed`.

8. **Create an application test event for a not-yet-built feature** — use `sam local generate-event` to produce a realistic API Gateway HTTP API payload, then hand-edit it to carry a `name` query string parameter. This is skill 3.3.1's "create application test events... JSON payloads for testing AWS Lambda":
   ```bash
   sam local generate-event apigateway http-api-proxy > events/hello_event.json

   python3 - << 'EOF'
   import json

   with open("events/hello_event.json") as f:
       event = json.load(f)

   event["queryStringParameters"] = {"name": "Esperanza"}

   with open("events/hello_event.json", "w") as f:
       json.dump(event, f, indent=2)
   EOF
   ```

9. **Write the failing test first (red)** — add a second test that loads the event fixture you just created and expects a personalized greeting the current handler doesn't produce yet:
   ```bash
   cat >> tests/unit/test_handler.py << 'EOF'


   def test_lambda_handler_returns_personalized_greeting():
       with open("events/hello_event.json") as f:
           event = json.load(f)

       response = app.lambda_handler(event, {})
       body = json.loads(response["body"])

       assert response["statusCode"] == 200
       assert body["message"] == "Hello, Esperanza!"
   EOF

   python3 -m pytest tests/unit -v
   ```
   The new test fails (`AssertionError`) because `app.py` still always returns `"Hello, World!"` — this is expected; you're confirming the test actually tests something before making it pass.

10. **Implement the feature and rerun the tests (green)** — update the handler to read the `name` query string parameter your test event carries:
    ```bash
    cat > hello_world/app.py << 'EOF'
    import json


    def lambda_handler(event, context):
        """Return a greeting. Defaults to 'World' when no name is supplied."""
        query_params = event.get("queryStringParameters") or {}
        name = query_params.get("name") or "World"

        return {
            "statusCode": 200,
            "body": json.dumps({"message": f"Hello, {name}!"}),
        }
    EOF

    python3 -m pytest tests/unit -v
    ```
    Both tests should now pass.

11. **Build the tested application** — confirm the unit-tested code still packages as a valid deployment artifact (no Docker required for a Zip-packaged Python function):
    ```bash
    sam build
    ```
    Look for `Build Succeeded` in the output.

## Validation

- `python3 -m pytest tests/unit -v` reports `2 passed` — the original default-greeting test and the personalized-greeting test (built from the generated test event) both succeed.
- `sam build` output ends with `Build Succeeded` and lists `Built Artifacts: .aws-sam/build`, confirming the handler you unit-tested also builds cleanly as a deployable Lambda package.
- `cat events/hello_event.json` shows a `queryStringParameters` object containing `"name": "Esperanza"` — the application test event you created and then consumed from a unit test.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. This lab created no AWS resources (no Lambda function, API, or IAM role was deployed), so there is nothing to tear down in the account. Run this only if you want to reclaim local disk space in the same CloudShell session.*

```bash
cd ..
rm -rf sam-unit-testing
```

## References

- AWS SAM Developer Guide — `sam init`, non-interactive usage and options (`--runtime`, `--name`, `--dependency-manager`, `--app-template`) — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/using-sam-cli-init.md
- AWS SAM CLI Command Reference — `sam init` — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-init.md
- AWS SAM Developer Guide — generated project directory structure (`tests/unit`, `tests/integration`, `events/`) — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/using-sam-cli-init.md
- AWS SAM Developer Guide — `sam build` usage and default (non-container) build behavior — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-using-build.md
- AWS SAM Developer Guide — `sam build` options, including `--use-container` and when Docker is required — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/using-sam-cli-build.md
- AWS SAM Developer Guide — `sam local generate-event`, generating and modifying sample service events — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/using-sam-cli-local-generate-event.md
- AWS SAM CLI Command Reference — `sam local generate-event` — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-local-generate-event.md
- AWS SAM Developer Guide — generating an API Gateway proxy event and using it with `sam local invoke` — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/using-sam-cli-local-invoke.md
- AWS SAM Developer Guide — `AWS::Serverless::Function` `HttpApi` event source — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-property-function-httpapi.md
- AWS SAM Developer Guide — `Globals` section (`Function.Timeout`, `Function.MemorySize`) — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-specification-template-anatomy-globals.md
- AWS SAM Developer Guide — installing the AWS SAM CLI with `pip` — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/manage-sam-cli-versions.md
- AWS SAM Developer Guide — Docker is required only for local invoke/`--use-container` builds, not for a plain Zip build — https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-docker.md
