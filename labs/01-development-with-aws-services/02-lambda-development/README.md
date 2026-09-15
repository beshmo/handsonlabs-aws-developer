# Domain 1, Task 2: Develop code for AWS Lambda

Source: [`specs/exam/Domain_1_Development_with_AWS_Services.md`](../../../specs/exam/Domain_1_Development_with_AWS_Services.md)

## Skills covered

| Skill | Description |
|---|---|
| 1.2.1 | Describe the access of private resources in VPCs from Lambda code |
| 1.2.2 | Configure Lambda functions (env vars, memory, concurrency, timeout, runtime, handler, layers, extensions, triggers, destinations) |
| 1.2.3 | Handle the event lifecycle and errors by using code (Lambda Destinations, dead-letter queues) |
| 1.2.4 | Write and run test code by using AWS services and tools |
| 1.2.5 | Integrate Lambda functions with AWS services |
| 1.2.6 | Tune Lambda functions for optimal performance |
| 1.2.7 | Use Lambda functions to process and transform data in near real time |

## Labs

| Lab ID | Title | File |
|---|---|---|
| D1-T2-L01 | Configuring Lambda: Environment Variables, Layers, and Triggers | `lab-01-lambda-env-layers-triggers.md` |
| D1-T2-L02 | Lambda Error Handling: Destinations and Dead-Letter Queues | `lab-02-lambda-destinations-dlq.md` |
| D1-T2-L03 | Lambda Access to Private VPC Resources | `lab-03-lambda-vpc-private-access.md` |
| D1-T2-L04 | Testing Lambda Functions Locally and in the Cloud | `lab-04-lambda-testing-local-cloud.md` |
| D1-T2-L05 | Tuning Lambda for Performance and Cost | `lab-05-lambda-performance-tuning.md` |
| D1-T2-L06 | Near-Real-Time Data Transformation with DynamoDB Streams | `lab-06-dynamodb-streams-transform.md` |

**Playground note:** all Lambda labs here operate within the KodeKloud limits of ≤256 MB memory, ≤10 s timeout, and no container images — see [`specs/kodekloud-aws-playground.md`](../../../specs/kodekloud-aws-playground.md).

See [`labs/INDEX.md`](../../INDEX.md) for the full skill-coverage matrix.
