# KodeKloud AWS Playground

The [KodeKloud AWS Playground](https://kodekloud.com/cloud-playgrounds/aws) provides a simplified learning environment where you can:

* Experiment with AWS services hands-on
* Learn by doing without creating an AWS account
* Reset environment easily if mistakes are made

## Supported AWS Regions

* **Region Code:** `us-east-1`

  * **Region Name:** US East (N. Virginia)
* **Region Code:** `us-west-2`

  * **Region Name:** US West (Oregon)
* **Region Code:** `us-east-2`

  * **Region Name:** US East (Ohio)

## Compute Services

### EC2 (Elastic Compute Cloud)

#### Allowed

* **Instance Types:**

  * `t2.nano`, `t2.micro`, `t2.small`
  * `t3.nano`, `t3.micro`, `t3.small`
  * `t2.medium`, `t3.medium`
* **Supported OS:**

  * RHEL
  * Amazon2
  * Windows
  * Ubuntu

#### EC2 CPU Credits

T-series instances (`t2`, `t3`, `t3a`, `t4g`) must operate in Standard CPU credit mode. Unlimited mode is not permitted. If detected, the instance will be reset to Standard and the session will be suspended/blocked.

#### Limits

* **Resource Limits:**

  * Max 2 vCPUs per instance
  * Max 4 GB vRAM per Instance
  * Max 10 concurrent instances
  * Total: Max 10 vCPUs & 20 GiB RAM
* **Storage:**

  * Max 30 GB per volume
  * GP2/GP3 only
* No more than 3 stopped instances are allowed
* Instance Shutdown Behaviour is Terminate
* No Spot Instances
* No Dedicated Hosts
* No Capacity Reservations
* No Scheduled Instances
* No FSRs (Fast Snapshot Restores)
* No VPN Connections/Gateways/Transit gateways/Traffic Mirroring

### AWS Lambda

#### Allowed

* **Supported Languages:**
  * All - Python, Java, NodeJs and more

* **Function Configuration:**
  * Basic monitoring
  * Function URLs supported (IAM auth only — public URLs blocked)
  * Layer usage permitted (own account only — no public or cross-account sharing)

#### Lambda Timeout

Lambda functions are subject to a maximum timeout of 10 seconds. Functions exceeding this will be automatically reset to 3 seconds. Timeouts greater than 30 seconds are considered a policy violation and will result in session suspension.

#### Limits

* Memory: Max 256 MB
* Timeout: Max 10 seconds
* Invocation Rate: Max 300/hour
* Container images not supported

### Elastic Beanstalk

#### Allowed

* **Environments:**
  * Web server supported
  * Worker supported

* **Platform:**
  * Latest versions only

#### Limits

* EC2 limits apply
* Basic load balancing
* Limited custom platforms

### Image Builder

#### Allowed

* **Valid schedules:** `rate(1 day)` or `cron` with a daily frequency.
* **Allowed Instance Types:**
  * `t3.micro`
  * `t3.small`
  * `t3.medium`
  * `t4g.micro`
  * `t4g.small`
  * `t4g.medium`

* **Components:**
  * Basic build components
  * Standard OS support

* **Pipeline:**
  * Basic build pipeline
  * Standard distribution

#### Limits

* Limited customization of components
* Limited testing for pipeline

### EC2 Instance Connect

#### Allowed

Basic operations are supported.

## Container Services

### ECS (Elastic Container Service)

#### Allowed

Basic operations are supported.

#### Limits

* **Resource Limits:**
  * Max CPU: 2048 units
  * Max Memory: 4096 MB

* **Task Definitions:**
  * Volume limitations
  * Network mode restrictions

### EKS (Elastic Kubernetes Service)

#### Allowed

Basic operations are supported.

* **Service Roles Permitted:**
  * Cluster Service Role: `eksClusterRole`
  * Node Service Role: `AmazonEKSNodeRole`

#### Limits

* **Pod Resource Limits**
  * Maximum CPU per Pod: 256 millicores
  * Maximum Memory per Pod: 512 MiB

* **Pod Count per Namespace**
  * Maximum Pods per Namespace: 3 pods

* **Cluster Resource Caps**
  * Cumulative CPU Cap per Cluster: 2000 millicores
  * Cumulative Memory Cap per Cluster: 4096 MiB

* **Account-Level Resource Caps**
  * Maximum Account-Wide CPU Cap: 6000 millicores (6 CPUs)
  * Maximum Account-Wide Memory Cap: 12288 MiB (12 GiB)

### ECR/ECR Public

#### Allowed

Basic operations are supported.

* **Repository Features:**
  * Basic operations
  * Scanning enabled
  * Lifecycle policies

* **Access:**
  * Standard authentication
  * Public repository support

## Storage Services

### S3 (Simple Storage Service)

#### Allowed

Basic operations are supported.

* **Operations:**
  * Standard bucket operations
  * Object management
  * Basic lifecycle rules

#### Limits

* No compliance mode locks
* Limited bucket policies
* Standard encryption required

### EBS (Elastic Block Storage)

#### Allowed

* **Operations:**
  * Basic snapshot management
  * Standard volume operations
  * Encryption supported

#### Resource Limits

* **Volume Types:**
  * GP2/GP3 only
  * Max 30 GB per volume

### EFS (Elastic File System)

#### Allowed

Basic operations are supported.

* **Performance:**
  * General Purpose only
  * Transition to IA after one day
  * Bursting throughput only
  * Standard IOPS limits

* **Features:**
  * Lifecycle management
  * Basic access points
  * Standard encryption

#### Resource Limits

* **File Systems:**
  * Max 2 per account
  * Max 5 GB per system
  * Growth: 1 GB/hour max

## Database Services

### RDS (Relational Database Service)

#### Allowed

* **Instance Classes allowed:**
  * `*.micro`, `*.small`, `*.medium`

* **Instance Types allowed:**
  * `db.t2.small`
  * `db.t3.small`
  * `db.t4g.small`
  * `db.t2.nano`
  * `db.t3.nano`
  * `db.t4g.nano`
  * `db.t2.micro`
  * `db.t3.micro`
  * `db.t4g.micro`
  * `db.t2.medium`
  * `db.t3.medium`
  * `db.t4g.medium`
  * Burst­able classes - T series

* **Engines:**
  * MariaDB
  * MySQL
  * PostgreSQL
  * Oracle SE 2
  * SQL Server Express Edition
  * Aurora MySQL/PostgreSQL

* **Specificities:**
  * Creating roles, attaching policies and passing roles specific to `rds-monitoring-role`, `rds-proxy-role-*` and `kk-rds-role`
  * Creating policies that include `rds-proxy` or `kk-rds-policy`.

#### Resource Limits

* **Storage:**
  * Max 30 GB
  * Standard IOPS only

* No Provisioned IOPS for RDS Storage

#### Key Considerations

* Use the Dev/Test or Free tier template, wherever prompted.
* Burstable (T-classes) to be used as the instance configuration. (Please refer to the instance types permitted)
* If prompted for Deployment options, please select Single-AZ DB instance deployment
* Stick to GP2/GP3, as there would be constraints on Provisioned IOPS

### DynamoDB

#### Allowed

* **Capacity:**
  * **Provisioned Throughput**
    * Read Capacity Units (RCU): 1
    * Write Capacity Units (WCU): 1

* **Table Class:**
  * PAY_PER_REQUEST (On-Demand)

* **Features:**
  * PartiQL supported
  * Point-in-time recovery
  * Basic backup features

#### Limits

* No global tables

### RDS Data API

#### Allowed

Basic operations are supported.

## Data Services

### Redshift Serverless

#### Allowed

* Max Allowed Capacity = 8 RPUs
* Max Allowed Retention Days = 1 (In Days)
* Max Allowed Workgroups = 1
* Max Retries = 30
* Retries Delay = 30 seconds

### Redshift

#### Allowed

**Cluster Count:**

* Maximum: 1 cluster per account.

**Node Count:**

* Maximum: 1 node per cluster.

**Instance Types:**

* Allowed: `dc2.large` only.

#### Limits

**Storage Capacity:**

* Minimum: 10 GB.
* Maximum: 10 GB.

### AWS EMR

#### Allowed

**Cluster Count**

* Maximum 1 cluster per account.

**Node Count per Cluster**

* Maximum 1 node per cluster.

**Allowed instance types**

* `m5.xlarge`
* `c1.medium`

**EBS Storage**

* Maximum 15 GB total EBS storage per cluster.

## Developer Tools

### CodeDeploy

#### Allowed

* **Allowed instance types:**
  * `t2.micro`
  * `t3.micro`
  * `t3.nano`
* EC2/On-premises
* Basic configurations
* Standard groups
* **Features:**
  * Rolling updates
  * Basic rollbacks
  * Standard hooks

### CodeStar

#### Allowed

Basic operations are supported.

### CodeArtifact

#### Allowed

Basic operations are supported.

### CloudShell

#### Allowed

Basic operations are supported.

## Monitoring & Management

### CloudWatch

#### Allowed

* **Metrics:**
  * Standard collection
  * Custom metrics
  * Basic dashboards

* **Logs:**
  * Log groups
  * Basic retention
  * Standard queries

* **Features:**
  * Basic alarms
  * Standard actions
  * Log insights

### CloudTrail

#### Allowed

* **Trails:**
  * Basic logging
  * Standard events
  * Organization trails

* **Features:**
  * Log validation
  * Basic insights
  * Standard retention

#### Limits

* Deletion Of CloudTrail Logs Not Allowed

### AWS Config

#### Allowed

* Standard remediation
* **Recording:**
  * Resource tracking
  * Basic history
  * Configuration snapshots

#### Limits

* Maximum of 50 AWS Config rules per account.
* Maximum of 1 active configuration recorder per account.
* Delivery channels should only exist for active configuration recorders.

### AWS Inspector

#### Allowed

* Inspector Findings
* Inspector Classic - Active Assessment Runs

#### Limits

* Maximum of 5 active assessment runs
* Maximum of 100 findings.

### CloudWatch RUM

#### Allowed

Basic operations are supported.

### Application Insights

#### Allowed

Basic operations are supported.

### CloudWatch Synthetics

#### Allowed

Basic operations are supported.

### CloudWatch Logs

#### Allowed

Basic operations are supported.

### X-Ray

#### Allowed

Basic operations are supported.

### Systems Manager (SSM)

#### Allowed

Basic operations are supported.

#### Limits

* SSM Run Command (Out of Scope)

## Networking & Content Delivery

### API Gateway

#### Allowed

* **API Types:**
  * REST APIs
  * HTTP APIs
  * WebSocket APIs

* **Features:**
  * Basic throttling
  * Standard authorizers
  * Basic caching
  * VPC links

* **Security:**
  * WAF integration
  * Standard encryption
  * Basic authentication

### Route 53

#### Allowed

Basic operations are supported.

#### Limits

* Route 53 Resolver Firewall Rules Not Allowed

### WAF and Shield

#### Allowed

* **Rule Groups:**
  * Custom rule groups supported

* **Protection Types:**
  * SQL injection
  * Cross-site scripting
  * Rate limiting
  * Geo blocks

* **Integration:**
  * ALB integration
  * API Gateway integration

### Elastic Load Balancing

#### Allowed

Basic operations are supported.

### Service Discovery

#### Allowed

Basic operations are supported.

### Internet Monitor

#### Allowed

Basic operations are supported.

## Application Integration

### Step Functions

#### Allowed

* All state machines must have logging enabled.
* Activities must be associated with an active state machine or execution.
* **State Machines:**
  * Standard workflows
  * Express workflows
* **Features:**
  * Basic states
  * Standard transitions
  * Error handling

### Kinesis

#### Allowed

Basic operations are supported.

#### Limits

**Data Streams:**

* Mode: Must be in PROVISIONED mode.
* Shard Count: Limited to 1 shard per stream.
* Retention Period: Maximum of 24 hours.
* Stream Count: Maximum of 2 streams per account.
* Data Throughput: Alerts generated for streams with more than 1 MB/s incoming data.

**Firehose:**

* Delivery Systems: Maximum of 2 delivery streams per account.
* Buffer Size and Interval: Maximum 5 MB buffer size, minimum 60 seconds interval.
* Data Throughput: Alerts generated for streams with more than 1 MB/s.

**Analytics:**

* SQL-based applications.
* Basic Processing

### EventBridge

#### Allowed

Basic operations are supported.

### SNS (Simple Notification Service)

#### Allowed

Basic operations are supported.

#### Also confirmed working (observed in the playground, lab `D1-T1-L03`)

* `sns:CreateTopic`, `sns:Publish` (with message attributes), `sns:DeleteTopic`.
* `sns:Subscribe` with protocol `sqs` (same-account subscriptions auto-confirm), including the `RawMessageDelivery` and `FilterPolicy` subscription attributes.
* `sqs:SetQueueAttributes` with a queue resource `Policy` that allows `sns.amazonaws.com` to `sqs:SendMessage` (scoped with `aws:SourceArn`) — SNS → SQS fan-out delivery works.

### SQS (Simple Queue Service)

#### Allowed

Basic operations are supported.

### Appmesh

#### Allowed

Basic operations are supported.

### AppSync

#### Allowed

Basic operations are supported.

### Apprunner

#### Allowed

Basic operations are supported.

## Security & Identity

### IAM (observed behavior)

*Not part of KodeKloud's official service list — recorded here from testing in the playground (`kk_labs_user_*`), so labs don't assume permissions the sandbox doesn't grant.*

#### Allowed (confirmed)

* `iam:CreateRole` — creating a role with a trust policy works.
* `iam:AttachRolePolicy` — attaching an AWS **managed** policy to a role works (e.g. `arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole`).

#### Denied (confirmed)

* `iam:PutRolePolicy` — inline role policies fail with `AccessDenied` (no identity-based policy allows it). Labs must attach managed policies instead. Only the pre-provisioned `EC2LabRole` supports `PutRolePolicy` (see Quick Start Guide below).

* `iam:PassRole` on user-created roles at the default path `/` — `lambda create-function --role arn:aws:iam::<acct>:role/<name>` fails with `AccessDeniedException ... not authorized to perform: iam:PassRole`.

#### Allowed workaround (confirmed)

* Create the role under the **`/service-role/`** path (`aws iam create-role --path /service-role/ ...`, the path the Lambda console uses) and pass it with `--role arn:aws:iam::<acct>:role/service-role/<name>`. `lambda create-function` then succeeds. **Every lab that creates a Lambda execution role must use this path.**

* No pre-provisioned role trusts `lambda.amazonaws.com` (`aws iam list-roles` in the tested account showed only service-linked roles; `EC2LabRole` was not present). The sandbox user also has an explicit deny from policy `AWS_EKSECSWithConditions` (e.g. `iam:ListAttachedUserPolicies`), so IAM is restricted via conditional policies.

* `lambda:DeleteEventSourceMapping` — `aws lambda delete-event-source-mapping` fails with `AccessDeniedException` (creating one with `create-event-source-mapping` works). Labs' cleanup must not depend on it. Deleting the function/queue does not remove the mapping either — it stays `Enabled` as an inert orphan until the session ends.

#### Also confirmed working

* `iam:DetachRolePolicy`, `iam:DeleteRole` (on a `/service-role/` role), `lambda:DeleteFunction`, `lambda:CreateEventSourceMapping` (SQS), `sqs:DeleteQueue`.

#### Not yet verified

* `PassRole` for other services (e.g. Step Functions, ECS task roles) — check per lab.

### Cognito

#### Allowed

* **User Pools:**
  * MFA required
  * **Password must meet the following requirements:**
    * Minimum length: 12 characters
    * Require uppercase letters
    * Require lowercase letters
    * Require numbers
    * Require symbols
  * **Advanced security features**
    * The `AdvancedSecurityMode` must be set to `"ENABLED"` in the `UserPoolAddOns` configuration.
    * User enumeration prevention must be enabled to prevent exposing valid user accounts during login attempts.
* **Identity Pools:**
  * Ensure at least one identity provider (IdP) is configured for secure user authentication.
  * Unauthenticated access must be disabled for all resources.
  * IAM roles assigned to users must not have overly permissive policies.

### Key Management Service

#### Allowed

Basic operations are supported.

### AWS Certificate Manager

#### Allowed

Basic operations are supported.

## Additional Tools / Services

### Application Auto Scaling

#### Allowed

* **Targets:**
  * ECS services
  * DynamoDB tables
  * Aurora replicas
* **Policies:**
  * Target tracking
  * Step scaling
  * Scheduled scaling

### Auto Scaling

#### Allowed

* **Groups:**
  * EC2 instance limits apply
* **Policies:**
  * Basic scaling rules
  * Standard metrics
  * Standard cooldown

#### Limits

* Denies Auto Scaling actions involving large instance types:
  * Instances ending in `*large` and `*metal`.
  * Specific medium instance families like `a*medium`, `c*medium`, `i*medium`, `m*medium`, `r*medium`, `x*medium`, and `t3a.medium`.

### Secrets Manager

#### Allowed

* **Secret Types:**
  * Database credentials
  * API keys
  * OAuth tokens
* **Rotation:**
  * Automatic rotation supported
  * Built-in RDS rotation
  * Custom Lambda rotation

### CloudFormation

#### Allowed

Basic operations are supported.

### CloudWatch Evidently

#### Allowed

Basic operations are supported.

### Tag Editor

#### Allowed

Basic operations are supported.

### AWS Management Console

#### Allowed

Basic operations are supported.

### AWS Evidently

#### Allowed

Basic operations are supported.

### AWS Cloud Development Kit

#### Allowed

Basic operations are supported.

### SSM Messages

#### Allowed

Basic operations are supported.

### SAM

#### Allowed

Basic operations are supported.

### ACM Private Certificate Authority

#### Allowed

Basic operations are supported.

### AWS OpenSearch

#### Allowed

* Instance types allowed: `t3.small.search`, `t3.medium.search`
* Max Allowed Domains: 1
* Max Data Node Count: 1
* Dedicated Master Nodes not permitted
* Maximum allowed IOPS per node: 3000
* Max allowed throughput: 125 MiB/s per node
* Max allowed VPC endpoints: 1

### AWS MediaConnect

#### Allowed

* Max Flows: 1
* Flow Size: Medium

### AWS DataSync

#### Allowed

* Max Agents: 1
* Max Tasks: 1
* Tasks to be in Basic Mode only (Enhanced Mode not permitted)

### AWS DirectoryService

#### Allowed

* Allowed Size: Small
* Allowed Edition: Standard
* Max 1 directory of each type:

  * Microsoft AD
  * AD Connector
  * SimpleAD

# Quick Start Guide

For a smooth experience, please read the guide below and pay attention to the highlighted text.

## Quick note on IAM roles

* `EC2LabRole` supports both `PutRolePolicy` and `PassRole` permissions.
* `SecretsManagerRDSMySQLRot-*` too could be utilised for RDS-specific scenarios

## EC2 Instances (Virtual Machines / Servers)

EC2 instances are virtual servers. They are elastic, meaning they can easily scale up or down.

* Use nano, micro, small, or medium sizes for t1, t2, and t3 instances.
* Use gp2 (General Purpose) volumes with a maximum storage size of 30GB.
* Maximum of 3 stopped instances. If exceeded, all are terminated.
* EC2 instances stop behavior is set to "terminate."
* Total number of EC2 instances is limited to 5.
* Ensure a default VPC exists, creating one if necessary.

## S3 - Object Storage

S3 buckets store files for easy upload and download.

* Bucket names must be unique. Add random numbers to ensure uniqueness.

## RDS - Relational Database Service

RDS supports MySQL, MariaDB, PostgreSQL, Oracle, Microsoft SQL Server, and Amazon Aurora.

* Use the Free tier for MySQL, MariaDB, and PostgreSQL.
* For other engines, use a Single DB Instance, Burstable Class, micro or small instance, and General Purpose SSD (gp2).

## EKS - Elastic Kubernetes Service

EKS quickly sets up a Kubernetes cluster.

* Cluster service role name: `eksClusterRole`
* CloudFormation stack name: `eks-cluster-stack`
* Limit of 3 EC2 nodes per node group.
* Allowed EC2 instance types:
  * `t2.micro`
  * `t2.nano`
  * `t2.small`
  * `t2.medium`
  * `t3.micro`
  * `t3.nano`
  * `t3.small`
  * `t3.medium`
* Limit of 3 Fargate profiles per cluster.

## ECR - Elastic Container Registry

Create and manage container repositories, similar to Docker Hub.

## Lambda - Serverless Computing

Run code without managing servers.

* Memory size is limited to 256 MB, and timeout to 10 seconds. Violations are updated to 128 MB and 3 seconds.
* If a function is invoked over 300 times in the last hour, it is deleted.

## CodePipeline - CI/CD Service

Automates build, test, and deploy phases.

* Compute types limited to `t3.micro`, `t3.small`, `t3.medium`. Violations updated to `t3.micro`.

## CodeDeploy - Deployment Service

Automates application releases.

* Allowed EC2 instance types:
  * `t2.micro`
  * `t3.micro`
  * `t3.nano`
* Violations updated to `t2.micro`.

## ECS - Elastic Container Service

Manages containerized applications.
* Limit of 3 container instances (EC2) per cluster. Violations result in cluster deletion.
* Allowed EC2 instance types same as EKS.
* Limit of 3 Fargate tasks per cluster.

## DynamoDB - NoSQL Database Service

Provides fast, scalable NoSQL databases.
* Provisioned throughput set to 1 read and 1 write capacity unit.
* Billing mode set to `"PAY_PER_REQUEST."`

## Restrictions

* CodeBuild Projects -> Project Creation/Updation denied for compute types other than these:
  * `BUILD_GENERAL1_SMALL`
  * `BUILD_LAMBDA_1GB`
  * `BUILD_LAMBDA_2GB`

| Restriction                          | Threshold                                                      | Action on Violation                        |
| ------------------------------------ | -------------------------------------------------------------- | ------------------------------------------ |
| Allowed Compute Types                | `BUILD_GENERAL1_SMALL`, `BUILD_LAMBDA_1GB`, `BUILD_LAMBDA_2GB` | Delete non-compliant projects              |
| Max Projects Per Account             | 5                                                              | Delete oldest projects (by creation time)  |
| Max Total Memory                     | 20 GB (across all projects)                                    | Delete projects with largest compute first |
| Max Total vCPU                       | 10 vCPU (across all projects)                                  | Delete projects with largest compute first |
| Max Build Duration                   | 10 minutes                                                     | Stop builds, delete project                |
| Max Concurrent Builds (account-wide) | 2                                                              | Stop oldest builds, delete those projects  |

| Restriction                              | Threshold  | Action on Violation                      |
| ---------------------------------------- | ---------- | ---------------------------------------- |
| Max Execution Time                       | 15 minutes | Stop execution                           |
| Max Concurrent Executions (account-wide) | 2          | Stop oldest executions, delete pipelines |
| Max Executions Per Hour (per pipeline)   | 5          | Stop all executions, delete pipeline     |
| Max Pipelines Per Account                | 3          | Delete oldest pipelines (by update time) |
