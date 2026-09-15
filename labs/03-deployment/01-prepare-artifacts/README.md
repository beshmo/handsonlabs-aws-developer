# Domain 3, Task 1: Prepare application artifacts to be deployed to AWS

Source: [`specs/exam/Domain_3_Deployment.md`](../../../specs/exam/Domain_3_Deployment.md)

## Skills covered

| Skill | Description |
|---|---|
| 3.1.1 | Manage the dependencies of the code module within the package |
| 3.1.2 | Organize files and a directory structure for application deployment |
| 3.1.3 | Use code repositories in deployment environments |
| 3.1.4 | Apply application requirements for resources (memory, cores) |
| 3.1.5 | Prepare application configurations for specific environments (e.g. AWS AppConfig) |

## Labs

| Lab ID | Title | File |
|---|---|---|
| D3-T1-L01 | Packaging Lambda Dependencies and Configuration | `lab-01-packaging-lambda-dependencies.md` |
| D3-T1-L02 | Using Code Repositories in Deployment Workflows | `lab-02-code-repositories-codeartifact.md` |
| D3-T1-L03 | Sizing Application Resources for Lambda and EC2 | `lab-03-sizing-app-resources.md` |
| D3-T1-L04 | Environment-Specific Configuration with AWS AppConfig | `lab-04-appconfig-environment-config.md` |

**Note:** AWS CodeCommit is not in scope for this exam version and is not offered to new AWS customers, so `D3-T1-L02` demonstrates "code repositories in deployment environments" via AWS CodeArtifact (private package repositories) plus a CodePipeline source-stage integration with an external Git provider.

See [`labs/INDEX.md`](../../INDEX.md) for the full skill-coverage matrix.
