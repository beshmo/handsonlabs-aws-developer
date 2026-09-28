# Lab D1-T1-L06 — Extending APIs with API Gateway (Transformations, Validation, Status Codes)

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.6` — Create, extend, and maintain APIs (for example, response/request transformations, enforcing validation rules, overriding status codes)

**Skills Practiced (secondary, cross-referenced):**
- None

**AWS Services Used:** Amazon API Gateway, AWS Lambda, IAM
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials; comes with the AWS CLI, Python 3, `zip`, and `jq` preinstalled). Conceptual familiarity with the Lambda execution role pattern from earlier labs. No resources from any other lab are used.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- API Gateway: REST APIs are allowed, along with standard authorizers and basic throttling; this lab uses `AuthorizationType NONE` on every method since authentication/authorization is a Domain 2 skill, not this one.
- Lambda: memory capped at 256 MB and timeout at 10 seconds — this lab uses 128 MB / 10 seconds, well inside the limit; the function needs no VPC access or layers.
- IAM: inline role policies (`iam:PutRolePolicy`) are denied; the Lambda execution role is created with `--path /service-role/` and only an AWS managed policy (`AWSLambdaBasicExecutionRole`) is attached via `attach-role-policy`, per the playground's confirmed IAM workaround.

## Purpose

A production API rarely hands a client the backend's raw request or response as-is — it reshapes payloads, rejects malformed input before it costs a backend invocation, and returns status codes that mean something to the caller instead of always returning `200`. In this lab you build a small "orders" REST API backed by a single Lambda function, wired with a **non-proxy (`AWS`) integration** so you control every transformation by hand: Velocity (VTL) mapping templates reshape the request going in and the response coming out (skill 1.1.6's "response/request transformations"), a JSON Schema model plus a request validator reject invalid POST bodies at the gateway before Lambda ever runs ("enforcing validation rules"), and integration responses selected by a regex against the Lambda error message turn a plain exception into a `404` while a default integration response turns a successful creation into `201` instead of the implicit `200` ("overriding status codes"). By the end you will have exercised all three examples the exam skill calls out, against one small, observable API.

## Steps

1. **Set shared variables** — a random suffix keeps every named resource collision-free across repeat runs:
   ```bash
   export SUFFIX=$(date +%s)
   export REGION=us-east-1
   export AWS_DEFAULT_REGION=us-east-1
   export API_NAME="orders-api-${SUFFIX}"
   export FUNCTION_NAME="orders-service-${SUFFIX}"
   export ROLE_NAME="orders-service-role-${SUFFIX}"
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   echo "$API_NAME / $FUNCTION_NAME / $ROLE_NAME"
   ```

2. **Create the Lambda execution role** — the playground denies inline role policies and denies `iam:PassRole` on roles created at the default `/` path, so the role must be created under `/service-role/` and get its permissions from an attached AWS managed policy:
   ```bash
   cat > trust-policy.json << 'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": { "Service": "lambda.amazonaws.com" },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF

   aws iam create-role \
       --role-name "$ROLE_NAME" \
       --path /service-role/ \
       --assume-role-policy-document file://trust-policy.json

   aws iam attach-role-policy \
       --role-name "$ROLE_NAME" \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

   export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/service-role/${ROLE_NAME}"
   sleep 10   # let the new role propagate before create-function references it
   ```

3. **Write and deploy the backend Lambda function** — `order_service.py` dispatches on an `action` field the request mapping templates will populate in later steps, not on a raw API Gateway proxy event (this is a non-proxy integration, so Lambda only ever sees what the mapping template builds). `get` looks up one of two seeded orders and raises an exception prefixed `OrderNotFound` when the ID isn't found — that prefix is what a later integration response's `selectionPattern` regex matches on to override the status code to `404`. `create` fabricates a new order ID and returns it with `status: CREATED`:
   ```bash
   cat > order_service.py << 'EOF'
   import uuid

   ORDERS = {
       "ord-1001": {"customerName": "Ada Lovelace", "amount": 42.50},
       "ord-1002": {"customerName": "Grace Hopper", "amount": 19.99},
   }


   def lambda_handler(event, context):
       action = event.get("action")

       if action == "create":
           order_id = f"ord-{uuid.uuid4().hex[:6]}"
           record = {"customerName": event["customerName"], "amount": event["amount"]}
           ORDERS[order_id] = record  # in-memory only; resets on cold start
           return {
               "orderId": order_id,
               "customerName": record["customerName"],
               "amount": record["amount"],
               "status": "CREATED",
           }

       if action == "get":
           order_id = event.get("orderId")
           if order_id not in ORDERS:
               raise Exception(f"OrderNotFound: order '{order_id}' does not exist")
           record = ORDERS[order_id]
           return {
               "orderId": order_id,
               "customerName": record["customerName"],
               "amount": record["amount"],
               "status": "FOUND",
           }

       raise Exception(f"InvalidAction: unsupported action '{action}'")
   EOF

   zip -q order-service.zip order_service.py

   aws lambda create-function \
       --function-name "$FUNCTION_NAME" \
       --runtime python3.12 \
       --role "$ROLE_ARN" \
       --handler order_service.lambda_handler \
       --zip-file fileb://order-service.zip \
       --timeout 10 \
       --memory-size 128

   aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME"
   export LAMBDA_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}/invocations"
   ```

4. **Create the REST API and its resource tree** — `create-rest-api`'s response includes the API's root resource ID directly, so no separate lookup call is needed; `/orders` and `/orders/{orderId}` are created under it:
   ```bash
   export API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --query 'id' --output text)
   export ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --query 'items[0].id' --output text)

   export ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id "$API_ID" \
       --parent-id "$ROOT_ID" \
       --path-part "orders" \
       --query 'id' --output text)

   export ORDER_ID_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id "$API_ID" \
       --parent-id "$ORDERS_RESOURCE_ID" \
       --path-part "{orderId}" \
       --query 'id' --output text)

   echo "API $API_ID: /orders=$ORDERS_RESOURCE_ID /orders/{orderId}=$ORDER_ID_RESOURCE_ID"
   ```

5. **Define a request model and validator (enforcing validation rules)** — the model is a JSON Schema draft-4 document requiring `customerName` and `amount`; the validator tells API Gateway to check the request body against a method's attached model *before* the integration runs, so a malformed POST never reaches Lambda:
   ```bash
   cat > order-input-schema.json << 'EOF'
   {
     "$schema": "http://json-schema.org/draft-04/schema#",
     "title": "OrderInput",
     "type": "object",
     "properties": {
       "customerName": { "type": "string" },
       "amount": { "type": "number" }
     },
     "required": ["customerName", "amount"]
   }
   EOF

   aws apigateway create-model \
       --rest-api-id "$API_ID" \
       --name "OrderInput" \
       --content-type "application/json" \
       --schema file://order-input-schema.json

   export VALIDATOR_ID=$(aws apigateway create-request-validator \
       --rest-api-id "$API_ID" \
       --name "validate-body" \
       --validate-request-body \
       --no-validate-request-parameters \
       --query 'id' --output text)
   ```

6. **Wire `POST /orders` — create, with request/response transformation and a status-code override** — the request mapping template reshapes the client's JSON body into the `{"action": "create", ...}` shape the Lambda function expects; `$input.json('$.field')` pulls each field out of the body as a JSON literal (already quoted for strings, unquoted for the number). The integration's *default* response (no `selectionPattern`, meaning "anything not otherwise matched") maps to method response `201` instead of the implicit `200`, and its own response template reshapes Lambda's flat JSON into a nested `order`/`meta` envelope — both a transformation and a status-code override in one step:
   ```bash
   cat > post-request.vtl << 'EOF'
   {
     "action": "create",
     "customerName": $input.json('$.customerName'),
     "amount": $input.json('$.amount')
   }
   EOF

   cat > post-response.vtl << 'EOF'
   #set($inputRoot = $input.path('$'))
   {
     "order": {
       "id": "$inputRoot.orderId",
       "customer": "$inputRoot.customerName",
       "amountUsd": $inputRoot.amount,
       "status": "$inputRoot.status"
     },
     "meta": {
       "apiRequestId": "$context.requestId"
     }
   }
   EOF

   aws apigateway put-method \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDERS_RESOURCE_ID" \
       --http-method POST \
       --authorization-type NONE \
       --request-validator-id "$VALIDATOR_ID" \
       --request-models application/json=OrderInput

   aws apigateway put-integration \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDERS_RESOURCE_ID" \
       --http-method POST \
       --type AWS \
       --integration-http-method POST \
       --uri "$LAMBDA_URI" \
       --passthrough-behavior WHEN_NO_MATCH \
       --request-templates "$(jq -n --rawfile tpl post-request.vtl '{"application/json": $tpl}')"

   aws apigateway put-method-response \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDERS_RESOURCE_ID" \
       --http-method POST \
       --status-code 201

   aws apigateway put-integration-response \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDERS_RESOURCE_ID" \
       --http-method POST \
       --status-code 201 \
       --response-templates "$(jq -n --rawfile tpl post-response.vtl '{"application/json": $tpl}')"
   ```

7. **Wire `GET /orders/{orderId}` — lookup, with a second transformation pair and an error-driven status override** — the request template pulls the path parameter with `$input.params('orderId')`; the success response template reshapes the found order the same way as step 6. A second integration response, whose `selectionPattern` regex `OrderNotFound.*` matches the Lambda exception message from step 3, maps to method response `404` and builds a clean client-facing error body instead of leaking Lambda's raw `errorMessage`/`errorType`/`stackTrace` payload:
   ```bash
   cat > get-request.vtl << 'EOF'
   {
     "action": "get",
     "orderId": "$input.params('orderId')"
   }
   EOF

   cat > get-response-200.vtl << 'EOF'
   #set($inputRoot = $input.path('$'))
   {
     "order": {
       "id": "$inputRoot.orderId",
       "customer": "$inputRoot.customerName",
       "amountUsd": $inputRoot.amount,
       "status": "$inputRoot.status"
     },
     "meta": {
       "apiRequestId": "$context.requestId"
     }
   }
   EOF

   cat > get-response-404.vtl << 'EOF'
   {
     "error": "OrderNotFound",
     "message": "$util.escapeJavaScript($input.path('$.errorMessage'))",
     "apiRequestId": "$context.requestId"
   }
   EOF

   aws apigateway put-method \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDER_ID_RESOURCE_ID" \
       --http-method GET \
       --authorization-type NONE \
       --request-parameters method.request.path.orderId=true

   aws apigateway put-integration \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDER_ID_RESOURCE_ID" \
       --http-method GET \
       --type AWS \
       --integration-http-method POST \
       --uri "$LAMBDA_URI" \
       --passthrough-behavior WHEN_NO_MATCH \
       --request-templates "$(jq -n --rawfile tpl get-request.vtl '{"application/json": $tpl}')"

   aws apigateway put-method-response --rest-api-id "$API_ID" --resource-id "$ORDER_ID_RESOURCE_ID" --http-method GET --status-code 200
   aws apigateway put-method-response --rest-api-id "$API_ID" --resource-id "$ORDER_ID_RESOURCE_ID" --http-method GET --status-code 404

   aws apigateway put-integration-response \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDER_ID_RESOURCE_ID" \
       --http-method GET \
       --status-code 200 \
       --response-templates "$(jq -n --rawfile tpl get-response-200.vtl '{"application/json": $tpl}')"

   aws apigateway put-integration-response \
       --rest-api-id "$API_ID" \
       --resource-id "$ORDER_ID_RESOURCE_ID" \
       --http-method GET \
       --status-code 404 \
       --selection-pattern "OrderNotFound.*" \
       --response-templates "$(jq -n --rawfile tpl get-response-404.vtl '{"application/json": $tpl}')"
   ```

8. **Grant API Gateway permission to invoke the Lambda function** — a non-proxy `AWS` integration still needs a resource-based Lambda permission (not an IAM role) so API Gateway is allowed to call it; the `source-arn` scopes the grant to only this API, any stage, any method:
   ```bash
   aws lambda add-permission \
       --function-name "$FUNCTION_NAME" \
       --statement-id "apigateway-invoke-${SUFFIX}" \
       --action lambda:InvokeFunction \
       --principal apigateway.amazonaws.com \
       --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*"
   ```

9. **Deploy the API to a stage** — nothing configured above is live until it's deployed:
   ```bash
   aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name dev
   export INVOKE_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev"
   echo "$INVOKE_URL"
   ```

10. **Exercise all three behaviors with `curl`** — a valid create, an invalid create rejected by the validator, a successful lookup, and a lookup that trips the 404 override:
    ```bash
    echo "--- POST /orders (valid body -> 201, transformed) ---"
    curl -s -w "\nHTTP %{http_code}\n" -X POST "$INVOKE_URL/orders" \
        -H "Content-Type: application/json" \
        -d '{"customerName":"Alan Turing","amount":99.95}'

    echo "--- POST /orders (missing 'amount' -> 400, rejected by the validator) ---"
    curl -s -w "\nHTTP %{http_code}\n" -X POST "$INVOKE_URL/orders" \
        -H "Content-Type: application/json" \
        -d '{"customerName":"Missing Amount"}'

    echo "--- GET /orders/ord-1001 (found -> 200, transformed) ---"
    curl -s -w "\nHTTP %{http_code}\n" "$INVOKE_URL/orders/ord-1001"

    echo "--- GET /orders/ord-9999 (not found -> 404 override) ---"
    curl -s -w "\nHTTP %{http_code}\n" "$INVOKE_URL/orders/ord-9999"
    ```

## Validation

- The valid `POST /orders` call returns `HTTP 201` (not the implicit `200`) with a body shaped `{"order": {"id": "ord-...", "customer": "Alan Turing", "amountUsd": 99.95, "status": "CREATED"}, "meta": {...}}` — confirming both the request template (client body → Lambda input) and the response template + status-code override (Lambda output → client envelope, `200` → `201`) ran.
- The invalid `POST /orders` call (missing `amount`) returns `HTTP 400` with an API Gateway–generated `"Invalid request body"` message, and never appears in the Lambda function's invocation count — proof the request validator blocked it at the gateway before any integration ran.
- `GET /orders/ord-1001` returns `HTTP 200` with `{"order": {"id": "ord-1001", "customer": "Ada Lovelace", "amountUsd": 42.5, "status": "FOUND"}, ...}`.
- `GET /orders/ord-9999` returns `HTTP 404` with `{"error": "OrderNotFound", "message": "OrderNotFound: order 'ord-9999' does not exist", ...}` — confirming the `selectionPattern` regex matched Lambda's raised exception and overrode the status code from the default to `404`, while also replacing Lambda's raw `errorMessage`/`errorType`/`stackTrace` payload with a clean client-facing shape.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

Deleting the REST API cascades to its resources, methods, models, and request validator, so no separate deletes are needed for those:

```bash
aws apigateway delete-rest-api --rest-api-id "$API_ID"
aws lambda delete-function --function-name "$FUNCTION_NAME"
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$ROLE_NAME"
rm -f trust-policy.json order_service.py order-service.zip order-input-schema.json \
      post-request.vtl post-response.vtl get-request.vtl get-response-200.vtl get-response-404.vtl
```
Confirm the API is gone:
```bash
aws apigateway get-rest-api --rest-api-id "$API_ID"   # should error: NotFoundException
```

## References

- AWS CLI `apigateway create-rest-api` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-rest-api.html
- AWS CLI `apigateway create-resource` / `get-resources` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-resource.html
- AWS CLI `apigateway create-model` — JSON Schema draft-4 model definition — https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-model.html
- AWS CLI `apigateway create-request-validator` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-request-validator.html
- AWS CLI `apigateway put-method` — `--request-validator-id`, `--request-models`, `--request-parameters` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/put-method.html
- AWS CLI `apigateway put-integration` — `AWS` (non-proxy) Lambda integration, `--request-templates`, `--passthrough-behavior` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/put-integration.html
- AWS CLI `apigateway put-method-response` / `put-integration-response` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/put-integration-response.html
- API Gateway Developer Guide — getting started with a Lambda non-proxy integration and its mapping templates — https://docs.aws.amazon.com/apigateway/latest/developerguide/getting-started-lambda-non-proxy-integration.html
- API Gateway Developer Guide — handling Lambda errors with `selectionPattern` to choose an integration response and status code — https://docs.aws.amazon.com/apigateway/latest/developerguide/handle-errors-in-lambda-integration.html
- API Gateway Developer Guide — mapping template reference (`$input.json`, `$input.params`, `$input.path`, `$context`) — https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-mapping-template-reference.html
- API Gateway Developer Guide — overriding request/response parameters and status codes — https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-override-request-response-parameters.html
- AWS CLI `apigateway create-deployment` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/create-deployment.html
- AWS CLI `lambda create-function` — https://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html
- AWS CLI `lambda add-permission` — granting `apigateway.amazonaws.com` invoke access scoped by `--source-arn` — https://docs.aws.amazon.com/cli/latest/reference/lambda/add-permission.html
- AWS CLI `iam create-role` (`--path`) / `attach-role-policy` — https://docs.aws.amazon.com/cli/latest/reference/iam/create-role.html
- AWS CLI `apigateway delete-rest-api` — https://docs.aws.amazon.com/cli/latest/reference/apigateway/delete-rest-api.html
