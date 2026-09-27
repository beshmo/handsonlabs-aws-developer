# Lab D1-T1-L05 — Building Resilient Application Code (Retries, Backoff, Circuit Breakers)

**Module:** Domain 1 — Development with AWS Services
**Task:** Task 1 — Develop code for applications hosted on AWS
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `1.1.5` — Create fault-tolerant and resilient applications in a programming language (for example, Java, C#, Python, JavaScript, TypeScript, Go)
- `1.1.13` — Implement resilient application code for third-party service integrations (for example, retry logic, circuit breakers, error handling patterns)

**Skills Practiced (secondary, cross-referenced):**
- None

**AWS Services Used:** AWS CloudShell, Amazon DynamoDB, AWS CLI
**Region:** us-east-1
**Prerequisites:** AWS CloudShell (pre-authenticated with the playground's credentials; comes with Python 3 + Boto3 preinstalled, so there is nothing extra to install). Conceptual familiarity with Python exception handling and with the SDK client pattern from D1-T1-L01. No resources from any other lab are used.
**Playground Constraints to Respect:**
- Work only in `us-east-1`, `us-west-2`, or `us-east-2` — this lab uses `us-east-1`.
- DynamoDB: provisioned throughput is capped at 1 Read Capacity Unit / 1 Write Capacity Unit (no global tables). This lab deliberately creates a table at that 1 WCU ceiling — it's what makes real `ProvisionedThroughputExceededException` throttling (and therefore observable retry/backoff behavior) happen on demand, safely, within a 30-minute lab, instead of simulating it.
- No Lambda, IAM roles, or other compute resources are created in this lab — everything runs as a Python script inside CloudShell against your own DynamoDB table, so none of the playground's Lambda or IAM path restrictions apply here.

## Purpose

Real applications depend on services that occasionally throttle, time out, or fail outright — the exam expects you to write code that tolerates this rather than crashing on the first error. In this lab you build two small, self-contained demonstrations of that idea. First, you create a DynamoDB table pinned to the playground's 1 WCU ceiling and fire a burst of concurrent writes at it through the AWS SDK for Python (Boto3), comparing a client with retries disabled against one configured with Boto3's built-in exponential-backoff retry mode — making "fault-tolerant application code" (skill 1.1.5) something you can see happen, not just configure. Second, because DynamoDB itself doesn't model a flaky *third-party* dependency, you simulate one in-process and wrap it with hand-rolled retry-with-backoff logic and a circuit breaker that trips open after repeated failures and short-circuits further calls until a cooldown elapses (skill 1.1.13) — logging every outcome back into the same DynamoDB table so you have a durable, queryable trace of the whole state machine.

## Steps

1. **Open CloudShell and set shared variables** — a random suffix keeps the table name collision-free, and pinning the Region for both the CLI and the SDK avoids surprises if CloudShell was launched elsewhere:
   ```bash
   export SUFFIX=$(date +%s)
   export TABLE_NAME="dva-resilience-demo-${SUFFIX}"
   export AWS_DEFAULT_REGION=us-east-1
   export AWS_REGION=us-east-1
   echo "$TABLE_NAME"
   ```

2. **Create a throughput-constrained DynamoDB table** — the playground allows at most 1 RCU / 1 WCU in provisioned mode; that ceiling is exactly what lets a burst of concurrent writes reliably exceed capacity and trigger `ProvisionedThroughputExceededException` a few seconds later, which is the fault the rest of this lab practices tolerating:
   ```bash
   aws dynamodb create-table \
       --table-name "$TABLE_NAME" \
       --attribute-definitions AttributeName=id,AttributeType=S \
       --key-schema AttributeName=id,KeyType=HASH \
       --billing-mode PROVISIONED \
       --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1

   aws dynamodb wait table-exists --table-name "$TABLE_NAME"
   echo "Table is ACTIVE"
   ```

3. **Write `retry_backoff_demo.py` — fault-tolerant SDK calls against a throttling dependency (skill 1.1.5)** — before any of the three phases below run, the script defensively re-confirms the table is actually still in `PROVISIONED` billing mode. This is not hypothetical: the KodeKloud playground's own quick-start guidance for DynamoDB notes that table billing mode gets set to `PAY_PER_REQUEST`, and a review pass of this lab observed exactly that in practice — a table created in Step 2 with `--billing-mode PROVISIONED` was silently auto-converted to `PAY_PER_REQUEST` by the playground roughly 5 minutes after creation, with no command in this lab causing it (`BillingModeSummary.LastUpdateToPayPerRequestDateTime` was set even though the script never calls `update_table` on its own). If that conversion happens while you're reading or debugging Steps 3-4 — plausible at a normal 30-minute lab pace — the whole throttling premise disappears with no visible error: writes simply stop throttling, and Step 4's Validation would then fail for a reason invisible to you. `ensure_provisioned_billing_mode()` guards against this: it calls `describe_table` and checks `Table.BillingModeSummary.BillingMode` (its absence also means `PROVISIONED`, per older API behavior, since that field is only populated once a table's billing mode has been explicitly set or changed). If it finds anything other than `PROVISIONED`, it calls `update_table` to switch the table back to `PROVISIONED` at the playground's 1 RCU / 1 WCU ceiling and waits for the table to return to `ACTIVE` before the warm-up drain below — which depends on that ceiling — runs. In the common case where nothing has drifted, this check adds well under a second; in the rare case it has to reset the table, it adds roughly 20-40 seconds. After that check, the script runs its three phases against the 1 WCU table. Phase one is a plain **sequential** warm-up loop (no threading at all): it fires one-shot `put_item` calls back-to-back through a client configured for zero retries (`max_attempts: 0` means exactly one total attempt, per Botocore's retry config), and stops the instant it observes a `ProvisionedThroughputExceededException` — that failure is proof, not an assumption, that DynamoDB's burst-capacity pool (up to 300 WCU-seconds of a 1 WCU table's unused throughput) is now exhausted. Because this loop is single-threaded, it doesn't depend on achieving real client-side concurrency at all — it only needs to issue requests faster than the table's 1 WCU/s replenishment rate, which a tight Python loop with no `sleep` does easily. Phase two is the actual `no-retry` demonstration: it runs immediately after the warm-up drains the pool, with no idle time for the ~1 WCU/s trickle to meaningfully refill it, so a small sequential batch of one-shot writes through that same zero-retry client is now landing against a table with ~0 burst credit and a hard 1-request/second ceiling — nearly every write in that batch throttles, deterministically, regardless of whether the requests are truly concurrent. Phase three is the `with-backoff` scenario, unchanged from before: 20 writes through a client configured with Boto3's `standard` retry mode and a higher `max_attempts`, which automatically retries the same throttling error with exponential backoff. Each result records how many retry attempts Botocore made, from `ResponseMetadata.RetryAttempts`:
   ```bash
   cat > retry_backoff_demo.py << 'EOF'
   import concurrent.futures
   import os
   import time

   import boto3
   from botocore.config import Config
   from botocore.exceptions import ClientError

   TABLE_NAME = os.environ["TABLE_NAME"]
   REGION = os.environ["AWS_REGION"]

   # DynamoDB reserves up to 5 minutes (300 seconds) of a table's unused
   # provisioned throughput as "burst capacity" that a spike of requests can
   # consume before real throttling kicks in. For a table pinned at 1 WCU,
   # that ceiling is at most 300 WCU-seconds of credit -- but exactly how
   # much of that pool is available right after `wait table-exists` varies.
   # Rather than assuming a fixed item count will exceed it, the warm-up
   # phase below drains the pool explicitly and stops the moment it
   # *observes* the pool running out, which is deterministic regardless of
   # the exact starting balance.
   WARMUP_MAX_ITEMS = 450     # safety cap; draining should trip well before this
   NO_RETRY_ITEM_COUNT = 20   # only needs to exceed ~1 write/sec once credit is gone
   BACKOFF_ITEM_COUNT = 20    # small on purpose: draining via backoff costs ~1 WCU/s
   MAX_CONCURRENCY = 100


   def make_client(config):
       return boto3.client("dynamodb", region_name=REGION, config=config)


   def ensure_provisioned_billing_mode(client):
       # Defensive check, run once at startup before anything else touches
       # the table. The KodeKloud playground has been observed to silently
       # auto-convert a table created with --billing-mode PROVISIONED to
       # PAY_PER_REQUEST a few minutes after creation, with no command in
       # this script causing it. If that happens mid-lab, the rest of this
       # demo's throttling premise silently breaks -- writes just start
       # succeeding, with no visible error. This switches the table back to
       # PROVISIONED at the playground's 1 RCU / 1 WCU ceiling whenever it
       # finds anything else, before the warm-up drain below (which depends
       # on that ceiling) runs.
       describe = client.describe_table(TableName=TABLE_NAME)
       billing_summary = describe["Table"].get("BillingModeSummary")
       # A table that has never had its billing mode changed omits
       # BillingModeSummary entirely (older API behavior); that also means
       # PROVISIONED, so only an explicit non-PROVISIONED value needs fixing.
       current_mode = billing_summary["BillingMode"] if billing_summary else "PROVISIONED"

       if current_mode == "PROVISIONED":
           print("--- billing-mode check: table is PROVISIONED, no action needed ---")
           return

       print(f"--- billing-mode check: table is unexpectedly {current_mode} "
             "(playground auto-conversion) -- switching back to PROVISIONED "
             "at 1 RCU / 1 WCU ---")
       client.update_table(
           TableName=TABLE_NAME,
           BillingMode="PROVISIONED",
           ProvisionedThroughput={"ReadCapacityUnits": 1, "WriteCapacityUnits": 1},
       )
       client.get_waiter("table_exists").wait(TableName=TABLE_NAME)
       print("--- billing-mode check: table is ACTIVE again in PROVISIONED mode ---")


   def write_item(client, item_id):
       start = time.time()
       try:
           response = client.put_item(TableName=TABLE_NAME, Item={"id": {"S": item_id}})
           retries = response["ResponseMetadata"].get("RetryAttempts", 0)
           return (item_id, "SUCCESS", retries, round(time.time() - start, 2))
       except ClientError as e:
           code = e.response["Error"]["Code"]
           return (item_id, f"FAILED:{code}", 0, round(time.time() - start, 2))


   def drain_burst_capacity(client):
       # Plain sequential loop -- no threading. This does not depend on
       # achieving real client-side parallelism at all: a tight
       # back-to-back loop with no sleep between requests still issues
       # writes far faster than the table's 1 WCU/s replenishment rate, so
       # the burst pool only shrinks while this runs. Stopping at the
       # first throttling failure means the pool is now *known*, not
       # assumed, to be exhausted.
       print(f"\n--- warm-up: draining burst capacity (sequential, {WARMUP_MAX_ITEMS} max) ---")
       for count in range(1, WARMUP_MAX_ITEMS + 1):
           _, status, _, _ = write_item(client, f"warmup-{count}")
           if status != "SUCCESS":
               print(f"  burst credit exhausted after {count} sequential writes ({status})")
               return count
       print(f"  WARNING: no throttling seen after {WARMUP_MAX_ITEMS} sequential writes; "
             "the no-retry demo below may not throttle as expected. Confirm the "
             "table's ProvisionedThroughput is really 1 WCU.")
       return None


   def run_burst(label, config, item_count, print_all, sequential=False, client=None):
       client = client or make_client(config)
       print(f"\n--- {label} ({item_count} writes) ---")
       if sequential:
           results = [write_item(client, f"{label}-{i}") for i in range(item_count)]
       else:
           with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENCY) as pool:
               futures = [pool.submit(write_item, client, f"{label}-{i}") for i in range(item_count)]
               results = [f.result() for f in futures]
       successes = [r for r in results if r[1] == "SUCCESS"]
       failures = [r for r in results if r[1] != "SUCCESS"]
       print(f"{label}: {len(successes)}/{item_count} succeeded, {len(failures)} failed")
       shown = results if print_all else (successes[:10] + failures[:10])
       for item_id, status, retries, elapsed in shown:
           print(f"  id={item_id:<16} status={status:<35} retry_attempts={retries:<2} elapsed={elapsed}s")
       if not print_all and len(results) > len(shown):
           print(f"  ... ({len(results) - len(shown)} more lines omitted; counts above cover all {item_count})")
       return successes, failures


   if __name__ == "__main__":
       no_retry_config = Config(retries={"max_attempts": 0, "mode": "standard"})
       no_retry_client = make_client(no_retry_config)

       ensure_provisioned_billing_mode(no_retry_client)

       drain_burst_capacity(no_retry_client)

       # No sleep here: the whole point of draining first is that the
       # table now has ~0 burst credit, so this phase must run while
       # that's still true. Any idle time would let the 1 WCU/s trickle
       # start refilling it before this batch runs.
       _, no_retry_failures = run_burst(
           "no-retry", no_retry_config, NO_RETRY_ITEM_COUNT, print_all=True,
           sequential=True, client=no_retry_client,
       )
       if len(no_retry_failures) < NO_RETRY_ITEM_COUNT // 2:
           raise SystemExit(
               f"Expected most of the {NO_RETRY_ITEM_COUNT} post-drain writes to be "
               f"throttled but only {len(no_retry_failures)} failed. Re-run the script; "
               "if this repeats, confirm the table's ProvisionedThroughput is really 1 WCU."
           )

       # A short 1-second pause (down from a previous 5s): the warm-up +
       # no-retry phases above already drove the table's burst credit to
       # ~0 on their own, so there's nothing left to "let drain". A
       # longer pause would only hand back more of the 1 WCU/s
       # replenishment, making it easier for the with-backoff writes
       # below to succeed without ever being throttled -- which would
       # defeat the point of this scenario.
       time.sleep(1)

       resilient_config = Config(retries={"max_attempts": 8, "mode": "standard"}, max_pool_connections=MAX_CONCURRENCY)
       run_burst("with-backoff", resilient_config, BACKOFF_ITEM_COUNT, print_all=True)
   EOF
   ```

4. **Run the retry/backoff demo** — the billing-mode check described in Step 3 runs first: normally a no-op adding well under a second, or roughly 20-40 seconds in the rare case the table needs to be switched back to `PROVISIONED`. The warm-up phase runs next: a tight sequential loop of one-shot writes (no threading, no delay between requests) that stops the instant it observes the table's burst credit run out. Exactly how many writes that takes varies significantly run to run — anywhere from several dozen to a few hundred, depending on how much burst credit the table had accumulated since creation — so treat the script's own printed count as the answer, not a number predicted here; either way it typically adds a few seconds up to around 15 seconds of wall-clock time. The `no-retry` block then runs immediately against that now-depleted table, so its 20 writes resolve in well under a second combined. After a short 1-second pause, the `with-backoff` scenario can then take up to about a minute, since only one write per second can actually land against the 1 WCU table once its burst credit runs out and the rest must wait out their backoff:
   ```bash
   python3 retry_backoff_demo.py
   ```
   The warm-up section prints how many sequential writes it took to exhaust the burst pool, then stops as soon as that happens — you do not need a fixed number of writes to reason about, only the observed failure. In the `no-retry` block that follows, the summary line should now report most or all of the 20 post-drain writes as `FAILED:ProvisionedThroughputExceededException` with `retry_attempts=0`: with the table's burst credit at ~0 and capped at 1 write/second, a client with no retry configuration surfaces that fault directly to the caller almost every time — the opposite of resilient code. The script exits with an error instead of a silent false pass if fewer than half of those 20 writes failed. In the `with-backoff` block, all or nearly all 20 writes should show `SUCCESS` — that is the reliable, meaningful signal that Botocore's `standard` retry mode is absorbing the same throttling that failed outright in the no-retry block. Some writes may also show `retry_attempts` greater than 0 when a request happens to land on a throttled attempt before eventually succeeding, which is a nice bonus confirmation that retries are really firing — but it is not required for a pass. Whether any given write's retry count comes out visibly nonzero depends on request timing (including network conditions between your client and DynamoDB) that can vary between runs even with identical code and table state, so 20/20 `SUCCESS` with `retry_attempts=0` across the board is still a pass.

5. **Write `circuit_breaker_demo.py` — retry logic and a circuit breaker around a flaky third-party dependency (skill 1.1.13)** — `flaky_payment_api` simulates a third-party payment gateway having a 7-call outage; `call_with_retry` retries a failed call once with a short backoff before giving up; `CircuitBreaker` tracks consecutive failures and, once a threshold is reached, moves to `OPEN` and short-circuits every call (without invoking the dependency at all) until a cooldown elapses, then allows one `HALF_OPEN` trial call to decide whether to `CLOSE` again or reopen. Every outcome is logged back into the same DynamoDB table so the whole state trace is durable and queryable:
   ```bash
   cat > circuit_breaker_demo.py << 'EOF'
   import os
   import random
   import time
   import uuid

   import boto3

   TABLE_NAME = os.environ["TABLE_NAME"]
   REGION = os.environ["AWS_REGION"]

   dynamodb = boto3.client("dynamodb", region_name=REGION)

   # Calls 1-7 simulate a sustained outage in the third-party dependency;
   # from call 8 onward the dependency has recovered.
   FAILING_CALLS = {1, 2, 3, 4, 5, 6, 7}


   class ThirdPartyServiceError(Exception):
       pass


   class CircuitOpenError(Exception):
       pass


   class CircuitBreaker:
       CLOSED, OPEN, HALF_OPEN = "CLOSED", "OPEN", "HALF_OPEN"

       def __init__(self, failure_threshold=3, recovery_timeout=3):
           self.failure_threshold = failure_threshold
           self.recovery_timeout = recovery_timeout
           self.state = self.CLOSED
           self.failure_count = 0
           self.opened_at = None

       def call(self, func, *args, **kwargs):
           if self.state == self.OPEN:
               if time.time() - self.opened_at >= self.recovery_timeout:
                   self.state = self.HALF_OPEN
                   print("  [circuit] cooldown elapsed -> HALF_OPEN, allowing one trial call")
               else:
                   raise CircuitOpenError("circuit is OPEN; short-circuiting call")

           try:
               result = func(*args, **kwargs)
           except ThirdPartyServiceError:
               self.failure_count += 1
               if self.state == self.HALF_OPEN or self.failure_count >= self.failure_threshold:
                   self.state = self.OPEN
                   self.opened_at = time.time()
                   print(f"  [circuit] tripped OPEN after {self.failure_count} consecutive failures")
               raise
           else:
               if self.state == self.HALF_OPEN:
                   print("  [circuit] trial call succeeded -> CLOSED")
               self.state = self.CLOSED
               self.failure_count = 0
               return result


   def call_with_retry(breaker, func, max_attempts=2, base_delay=0.3):
       for attempt in range(1, max_attempts + 1):
           try:
               return breaker.call(func)
           except CircuitOpenError:
               raise
           except ThirdPartyServiceError as e:
               if attempt == max_attempts:
                   raise
               delay = base_delay * (2 ** (attempt - 1)) + random.uniform(0, 0.1)
               print(f"  [retry] attempt {attempt} failed ({e}); backing off {delay:.2f}s")
               time.sleep(delay)


   def flaky_payment_api(call_num):
       if call_num in FAILING_CALLS:
           raise ThirdPartyServiceError(f"simulated gateway outage on call {call_num}")
       return "payment-authorized"


   def log_result(run_id, call_num, status, breaker_state):
       dynamodb.put_item(
           TableName=TABLE_NAME,
           Item={
               "id": {"S": f"circuit-breaker#{run_id}#{call_num:02d}"},
               "status": {"S": status},
               "breaker_state": {"S": breaker_state},
           },
       )


   if __name__ == "__main__":
       run_id = uuid.uuid4().hex[:8]
       breaker = CircuitBreaker(failure_threshold=3, recovery_timeout=3)

       for call_num in range(1, 16):
           print(f"Call {call_num:02d} (breaker={breaker.state}):")
           try:
               result = call_with_retry(breaker, lambda: flaky_payment_api(call_num))
               print(f"  -> {result}")
               log_result(run_id, call_num, "SUCCESS", breaker.state)
           except CircuitOpenError as e:
               print(f"  -> short-circuited: {e}")
               log_result(run_id, call_num, "SHORT_CIRCUITED", breaker.state)
           except ThirdPartyServiceError as e:
               print(f"  -> gave up after retries: {e}")
               log_result(run_id, call_num, "FAILED", breaker.state)
           time.sleep(1)

       print(f"\nRun ID: {run_id}")
   EOF
   ```

6. **Run the circuit breaker demo** — read the console output as it runs; it prints every state transition as it happens:
   ```bash
   python3 circuit_breaker_demo.py
   ```
   You should see calls 1-3 fail (the third one trips the breaker `OPEN`), a run of `short-circuited` results while the breaker stays `OPEN` and never calls `flaky_payment_api` again, then a `HALF_OPEN` trial once the cooldown elapses. Because the simulated outage only lasts through call 7, the first trial that lands on call 8 or later succeeds and closes the breaker; if a trial lands earlier (while the outage is still active) the breaker simply reopens and tries again a few calls later — either way, by call 15 the breaker is `CLOSED` and every remaining call succeeds. Note the `Run ID` printed at the end; you'll use it to query DynamoDB in the next step.

7. **Query the persisted state trace** — `status` is a DynamoDB reserved word, so the scan uses `#s` as a placeholder via `--expression-attribute-names` (substitute the Run ID printed in the previous step):
   ```bash
   export RUN_ID=<paste the Run ID printed above>
   aws dynamodb scan \
       --table-name "$TABLE_NAME" \
       --filter-expression "begins_with(id, :prefix)" \
       --expression-attribute-values "{\":prefix\":{\"S\":\"circuit-breaker#${RUN_ID}#\"}}" \
       --projection-expression "id, #s, breaker_state" \
       --expression-attribute-names '{"#s":"status"}' \
       --query 'sort_by(Items, &id.S)'
   ```
   The 15 returned items are the exact sequence your script logged: `status` values move from `FAILED` to `SHORT_CIRCUITED` to (eventually) `SUCCESS`, and `breaker_state` traces `CLOSED` → `OPEN` → `HALF_OPEN`-triggered `SUCCESS`/`FAILED` → `CLOSED`.

## Validation

- In `retry_backoff_demo.py`, the sequential warm-up loop first drains the table's burst credit to ~0 and prints the exact write count at which the first `ProvisionedThroughputExceededException` appeared. Immediately afterward, in the `no-retry` block, most or all of the 20 post-drain one-shot writes show `FAILED:ProvisionedThroughputExceededException` with `retry_attempts=0`. This no longer depends on achieving real thread-level concurrency: with burst credit exhausted and only 1 WCU/s of replenishment available, a sequential loop of writes already arrives far faster than the table can absorb, so a client with retries disabled surfaces the throttling fault directly almost every time.
- In the `with-backoff` block, all or nearly all 20 writes show `SUCCESS` — this is the hard pass criterion, since Boto3's `standard` retry mode is designed to absorb the same throttling that failed outright in the no-retry block. Some writes may also show `retry_attempts` greater than 0, which is a bonus confirmation that retries actually fired, but it is not required: whether a given write's retry count comes out visibly nonzero depends on request timing that can vary run to run even with identical code and table state.
- `circuit_breaker_demo.py`'s console output contains a `tripped OPEN` line after 3 consecutive failures, at least one `short-circuited` result while the breaker is `OPEN`, and a `HALF_OPEN` / `-> CLOSED` (or reopen-and-retry) sequence, ending with calls succeeding once the simulated outage clears.
- The `aws dynamodb scan` in step 7 returns 15 items for the printed Run ID whose `status` values include `FAILED`, `SHORT_CIRCUITED`, and `SUCCESS`, and whose final entries (highest call number) show `breaker_state = CLOSED`.

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

Note: if the table happens to be mid-transition between billing modes (see Step 3's billing-mode check), `delete-table` can transiently fail with `ResourceInUseException: ... is in the process of being updated`. If that happens, wait about 30 seconds and re-run the command — no other workaround is needed.

```bash
aws dynamodb delete-table --table-name "$TABLE_NAME"
rm -f retry_backoff_demo.py circuit_breaker_demo.py
```
Confirm the table is gone:
```bash
aws dynamodb describe-table --table-name "$TABLE_NAME"   # should error: ResourceNotFoundException
```

## References

- Botocore `Config` class — retry configuration (`retries={'max_attempts': ..., 'mode': ...}`) and `max_pool_connections` — https://github.com/boto/botocore/blob/develop/docs/source/reference/config.rst
- Amazon DynamoDB Developer Guide — burst capacity (DynamoDB reserves up to 5 minutes of a table's unused provisioned throughput as burst credit) — https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/burst-adaptive-capacity.html
- Boto3 retries guide — retry modes and the throttling/transient exceptions each mode retries automatically (including `ProvisionedThroughputExceededException`) — https://github.com/boto/boto3/blob/develop/docs/source/guide/retries.rst
- Boto3 error handling guide — catching `ClientError` and service-specific exceptions — https://github.com/boto/boto3/blob/develop/docs/source/guide/error-handling.rst
- AWS CLI `dynamodb create-table` (provisioned throughput) — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/create-table.html
- AWS CLI `dynamodb wait table-exists` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/wait/table-exists.html
- AWS CLI `dynamodb describe-table` — `BillingModeSummary.BillingMode` output field, used by the boto3 `describe_table` call in the defensive billing-mode check — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/describe-table.html
- AWS CLI `dynamodb update-table` — `--billing-mode` / `--provisioned-throughput`, used by the boto3 `update_table` call to switch a table back to `PROVISIONED` at 1 RCU/1 WCU — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/update-table.html
- Boto3 low-level client waiters guide — `get_waiter()` / `wait()` pattern, used here as `client.get_waiter("table_exists").wait(...)` after the billing-mode reset — https://github.com/boto/boto3/blob/develop/docs/source/guide/clients.rst
- AWS CLI `dynamodb scan` — `--filter-expression`, `--expression-attribute-names`, `--expression-attribute-values` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/scan.html
- AWS CLI `--expression-attribute-names` — working around reserved words like `status` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/delete-item.html
- AWS CLI `dynamodb delete-table` — https://docs.aws.amazon.com/cli/latest/reference/dynamodb/delete-table.html
