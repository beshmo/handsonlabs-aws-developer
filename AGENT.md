# AGENT.md — Operating Rules for This Repo

This repo is a self-paced, hands-on lab course for the **AWS Certified Developer – Associate (DVA-C02)** exam. Every lab is executed by a student in the **KodeKloud AWS Playground**, a shared sandbox with hard resource and time limits. This file is the contract any agent (this session or a future one) must follow when creating or editing a lab.

## Source of truth

Never invent a skill, service, or constraint. Everything traces back to:

- `specs/exam/Domain_1_Development_with_AWS_Services.md`
- `specs/exam/Domain_2_Security.md`
- `specs/exam/Domain_3_Deployment.md`
- `specs/exam/Domain_4_Troubleshooting_and_Optimization.md`
- `specs/exam/In-Scope_AWS_Services.md` — a lab may only use services on this list.
- `specs/kodekloud-aws-playground.md` — a lab may never require anything this document disallows or exceeds.

The master catalog is `labs/INDEX.md`. It is the single source of truth for what labs exist, their status, and which exam skill IDs they cover. Any new or changed lab must be reflected there.

## Hard constraints (non-negotiable)

1. **Self-contained.** Every lab creates every resource it needs and never assumes a resource left over from another lab.
2. **~30 minutes.** A lab's Purpose through Validation must be completable in about 30 minutes. KodeKloud sessions run out around the 1-hour mark; students need margin. Cleanup is a separate, optional, untimed step (see constraint 4) and does not count toward this budget. If a skill cluster can't fit in 30 minutes, split it into two labs rather than stretch the time box.
3. **Playground limits are absolute.** Before writing any step, check `specs/kodekloud-aws-playground.md` for the services involved and stay inside every limit, for example:
   - Lambda: max 256 MB memory, max 10 s timeout, no container images, max ~300 invocations/hour.
   - EC2: `t2`/`t3` nano–medium only, max 2 vCPU / 4 GB RAM per instance, GP2/GP3 volumes ≤30 GB, Standard CPU credit mode only, no Spot/Dedicated Hosts/Capacity Reservations.
   - DynamoDB: PAY_PER_REQUEST or provisioned 1 RCU / 1 WCU only, no global tables.
   - Regions: only `us-east-1`, `us-west-2`, `us-east-2`.
   - RDS: `*.micro`/`*.small`/`*.medium` burstable classes only, Single-AZ, GP2/GP3, ≤30 GB, no Provisioned IOPS.
   - IAM: roles can be created and AWS managed policies attached, but inline role policies (`iam:PutRolePolicy`) are denied, and a role can only be passed to Lambda if created with `--path /service-role/` — see the IAM section of the playground doc, and don't assume an IAM action works just because IAM is an in-scope exam service.
   - Any other service: check the relevant section of the playground doc before writing steps.
   This list is illustrative, not exhaustive — always re-check the source doc for the services a lab actually touches.
4. **Cleanup is documented, not timed or mandatory.** Every lab ends with an optional `## Cleanup (Optional)` section that tears down every resource it created, in dependency order. The KodeKloud Playground automatically terminates and cleans up all resources when a session ends, so cleanup isn't required to avoid leftover cost. Document it anyway, as a courtesy for a student who wants to free up quota to fit another lab into the same running session — the playground's account-wide quotas (e.g., max 10 EC2 instances, max 2 Kinesis streams, max 1 OpenSearch domain) still apply within a session.

## Mandatory use of context7 for technical accuracy

Before writing **any** AWS CLI command, SDK call, CDK construct, SAM/CloudFormation template snippet, or console click-path in a lab, resolve and query **context7** for the current documentation of the tool/service involved (`aws-cli`, `aws-cdk-lib`, the relevant language SDK, AWS SAM, CloudFormation). Do this even when the syntax seems familiar — training data may be stale, and flags/APIs get renamed or deprecated. Never guess a flag, parameter, or resource property. This applies per the user's global context7 rule and is enforced for every lab generated via the `build-lab` skill.

## Lab file naming and location

```
labs/<module-num>-<domain-slug>/<task-num>-<task-slug>/lab-<seq>-<slug>.md
```

Lab ID shorthand (used in `labs/INDEX.md` and cross-references): `D<domain>-T<task>-L<seq>`, e.g. `D1-T2-L03`.

**Primary vs. secondary skill filing:** a lab is placed in the folder of the single domain/task it most centrally teaches. If it also exercises skills from other domains/tasks, list those as *secondary* in the lab's header and in `labs/INDEX.md` — do not duplicate the file into multiple folders.

## Required lab header template

Every lab file must start with exactly this structure:

```markdown
# Lab D<domain>-T<task>-L<seq> — <Title>

**Module:** Domain <N> — <Domain Name>
**Task:** Task <N> — <Task Name>
**Estimated Duration:** ~30 minutes (Purpose → Validation; Cleanup is optional and untimed)
**Skills Practiced (primary):**
- `X.Y.Z` — <verbatim skill text from the relevant specs/exam/Domain_*.md>

**Skills Practiced (secondary, cross-referenced):**
- `X.Y.Z` (see Domain N Task M) — <verbatim skill text>

**AWS Services Used:** <comma-separated list, must all appear in specs/exam/In-Scope_AWS_Services.md>
**Region:** us-east-1 | us-west-2 | us-east-2
**Prerequisites:** AWS CLI configured against the KodeKloud playground credentials; <any prior *conceptual* knowledge only — never a dependency on another lab's leftover resources>
**Playground Constraints to Respect:**
- <bullet(s) copied/paraphrased from specs/kodekloud-aws-playground.md relevant to this lab's services>

## Purpose

<2-4 sentences: what the student builds, and why it matters for the exam skills listed above.>

## Steps

1. **<Step title>** — brief description of what this step does and why.
2. **<Step title>** — ...
   (continue; each step gets a one-line rationale, not a full paragraph)

## Validation

- <How the student confirms the lab worked — a CLI command whose output proves success, or a console check.>

## Cleanup (Optional)

*Optional — the KodeKloud Playground automatically terminates and removes all session resources when your session ends. Run this only if you want to tear resources down sooner, e.g. to free up quota for another lab in the same session.*

- <Explicit teardown command/step for every resource created, in dependency order.>

## References

- <Official AWS documentation links, verified current via context7 at authoring time.>
```

## Style guide

- Prefer **AWS CLI** commands for hands-on reps — the exam explicitly tests CLI/SDK skills (1.1.9, 2.1.3, 2.1.4). Use the AWS Console only when a skill is console-specific (e.g., API Gateway stage configuration UI) or CLI would be needlessly awkward for a 30-minute lab.
- IAM policies shown in a lab must be least-privilege and scoped to the exact resources the lab creates — never `"Resource": "*"` unless the action genuinely requires it (e.g., `iam:ListRoles`).
- Everything in a lab should run at effectively zero cost within playground free-tier-eligible quotas; call out anywhere a lab could incur cost if run outside the playground.
- Write steps for a student who knows AWS basics but is preparing for the *associate* exam — don't over-explain fundamentals covered elsewhere, do explain the specific behavior the skill is testing.
- No filler. Every step exists because it demonstrates a skill from the header's list.

## Definition of Done for a lab

A lab is done when:

- [ ] The header matches the required template exactly, with correct Lab ID, real skill IDs and verbatim skill text, and only services from `In-Scope_AWS_Services.md`.
- [ ] Every command/parameter was checked against context7 docs, not assumed from training data.
- [ ] Every resource/instance type/size/region choice fits `specs/kodekloud-aws-playground.md`.
- [ ] The lab is self-contained and its Purpose–Validation flow is realistically completable in ~30 minutes.
- [ ] A `## Cleanup (Optional)` section documents teardown for every resource created, in dependency order.
- [ ] `labs/INDEX.md`'s row for this Lab ID has its `Status` updated (`Planned` → `Drafted`, and → `Reviewed` once a human has run it).

## How to add or generate a lab

Use the `build-lab` skill: `/build-lab <lab-id>` (e.g. `/build-lab D2-T2-L03`). It reads the catalog row from `labs/INDEX.md`, loads this file's rules and template, verifies syntax via context7, writes the lab file, and updates the catalog status. See `.claude/skills/build-lab/SKILL.md` for its exact workflow.

If a genuinely new lab is needed (a skill turns out to be uncovered, or scope changes), add its row to `labs/INDEX.md` first — including the skill-coverage matrix update — before generating content, so the catalog never drifts out of sync with the files on disk.
