# Domain 1, Task 3: Use data stores in application development

Source: [`specs/exam/Domain_1_Development_with_AWS_Services.md`](../../../specs/exam/Domain_1_Development_with_AWS_Services.md)

## Skills covered

| Skill | Description |
|---|---|
| 1.3.1 | Describe high-cardinality partition keys for balanced partition access |
| 1.3.2 | Describe database consistency models (strongly consistent, eventually consistent) |
| 1.3.3 | Describe differences between query and scan operations |
| 1.3.4 | Define Amazon DynamoDB keys and indexing |
| 1.3.5 | Serialize and deserialize data to provide persistence to a data store |
| 1.3.6 | Use, manage, and maintain data stores |
| 1.3.7 | Manage data lifecycles |
| 1.3.8 | Use data caching services |
| 1.3.9 | Use specialized data stores based on access patterns (e.g. Amazon OpenSearch Service) |

## Labs

| Lab ID | Title | File |
|---|---|---|
| D1-T3-L01 | DynamoDB Table Design: Partition Keys and Indexes | `lab-01-dynamodb-keys-indexes.md` |
| D1-T3-L02 | Query vs Scan and Consistency Models in DynamoDB | `lab-02-dynamodb-query-scan-consistency.md` |
| D1-T3-L03 | Externalizing State: Stateless Lambda + DynamoDB CRUD | `lab-03-stateless-lambda-dynamodb-crud.md` |
| D1-T3-L04 | Managing Data Lifecycles: DynamoDB TTL and S3 Lifecycle Rules | `lab-04-dynamodb-ttl-s3-lifecycle.md` |
| D1-T3-L05 | Caching Strategies: ElastiCache and DynamoDB Accelerator (DAX) | `lab-05-elasticache-dax-caching.md` |
| D1-T3-L06 | Full-Text Search with Amazon OpenSearch Service | `lab-06-opensearch-full-text-search.md` |

`D1-T3-L03` also closes the loop on Task 1's stateful-vs-stateless skill (1.1.2) by demonstrating a stateless Lambda function backed by DynamoDB.

**Playground note:** use DynamoDB PAY_PER_REQUEST or 1 RCU/1 WCU provisioned capacity only, no global tables; OpenSearch is capped at 1 domain / 1 data node — see [`specs/kodekloud-aws-playground.md`](../../../specs/kodekloud-aws-playground.md).

See [`labs/INDEX.md`](../../INDEX.md) for the full skill-coverage matrix.
