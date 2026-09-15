# Domain 2, Task 1: Implement authentication and/or authorization for applications and AWS services

Source: [`specs/exam/Domain_2_Security.md`](../../../specs/exam/Domain_2_Security.md)

## Skills covered

| Skill | Description |
|---|---|
| 2.1.1 | Use an identity provider to implement federated access (e.g. Amazon Cognito, IAM) |
| 2.1.2 | Secure applications by using bearer tokens |
| 2.1.3 | Configure programmatic access to AWS |
| 2.1.4 | Make authenticated calls to AWS services |
| 2.1.5 | Assume an IAM role |
| 2.1.6 | Define permissions for IAM principals |
| 2.1.7 | Implement application-level authorization for fine-grained access control |
| 2.1.8 | Handle cross-service authentication in microservice architectures |

## Labs

| Lab ID | Title | File |
|---|---|---|
| D2-T1-L01 | Federated Access with Amazon Cognito User Pools | `lab-01-cognito-federated-access.md` |
| D2-T1-L02 | Securing APIs with Bearer Tokens (Cognito + API Gateway Authorizer) | `lab-02-bearer-tokens-api-authorizer.md` |
| D2-T1-L03 | Programmatic Access and Authenticated AWS Calls (CLI, SDK, STS) | `lab-03-programmatic-access-sts.md` |
| D2-T1-L04 | Cross-Service Authentication with IAM Roles (STS AssumeRole) | `lab-04-cross-service-assume-role.md` |
| D2-T1-L05 | Defining Least-Privilege IAM Permissions | `lab-05-least-privilege-iam.md` |
| D2-T1-L06 | Fine-Grained Application-Level Authorization | `lab-06-app-level-authorization.md` |

**Playground note:** Cognito user pools here must enforce MFA, the 12-character/complexity password policy, and `AdvancedSecurityMode: ENABLED` — see [`specs/kodekloud-aws-playground.md`](../../../specs/kodekloud-aws-playground.md).

See [`labs/INDEX.md`](../../INDEX.md) for the full skill-coverage matrix.
