# handsonlabs-aws-developer

Guided, hands-on labs to practice every Task and Skill in the [AWS Certified Developer – Associate (DVA-C02)](specs/exam/) exam guide. Labs run entirely in the [KodeKloud AWS Playground](specs/kodekloud-aws-playground.md) — no personal AWS account or bill required.

## Core concepts

**The playground is the constraint, not an afterthought.** Every lab is designed to work within the KodeKloud AWS Playground's resource limits (e.g. Lambda capped at 256 MB / 10 s, DynamoDB on-demand or 1 RCU/1 WCU, EC2 `t2`/`t3` nano–medium only, 3 fixed regions). See [`specs/kodekloud-aws-playground.md`](specs/kodekloud-aws-playground.md) for the full list before you assume a step will work.

**Labs are self-contained and ~30 minutes long.** Each lab creates every resource it uses and tears it down at the end — no lab depends on another lab's leftovers. That also means you can do them in any order, and each one comfortably fits inside a single KodeKloud session (which itself runs out around the 1-hour mark).

**Labs are organized by exam Domain and Task.** The folder layout mirrors the exam guide directly:
```
labs/
  01-development-with-aws-services/   Domain 1
  02-security/                        Domain 2
  03-deployment/                      Domain 3
  04-troubleshooting-and-optimization/ Domain 4
```
Each domain folder has one subfolder per exam Task, and each Task folder has a `README.md` listing the skills and labs it covers.

**`labs/INDEX.md` is the single source of truth.** It catalogs all 80 planned labs with their title, file path, exam skill IDs (primary + secondary), AWS services used, and a full skill-coverage matrix mapping every one of the exam's 101 skill IDs to the lab(s) that teach it — so you can confirm nothing is missing, or jump straight to the skill you're weakest on.

**Every lab has the same anatomy:** a header (skills practiced, services used, region, prerequisites, playground constraints), a Purpose section, numbered Steps, a Validation section to confirm you did it right, and a mandatory Cleanup section. Read Cleanup before you start a lab, not after — know what you're on the hook to tear down.

**Labs favor the AWS CLI / SDK over the console** wherever practical, since that's what the exam actually tests (skills like 1.1.9, 2.1.3, 2.1.4). Most labs run entirely from AWS CloudShell, so there's no local setup.

## Getting started

1. Read [`labs/README.md`](labs/README.md) for the full student orientation (how to pick a lab, recommended order, what to expect).
2. Browse [`labs/INDEX.md`](labs/INDEX.md) for the complete catalog and skill-coverage matrix.
3. Open a lab file and follow it top to bottom: Purpose → Steps → Validation → Cleanup.

## For maintainers: extending the course

This repo's lab content is generated incrementally, one lab at a time, to keep quality and AWS-syntax accuracy high:
- [`AGENT.md`](AGENT.md) defines the non-negotiable rules every lab must follow (playground limits, ~30 min/self-contained, mandatory [context7](https://context7.com) verification of any CLI/SDK/IaC syntax, the required header template, style guide, Definition of Done).
- [`.claude/skills/build-lab/SKILL.md`](.claude/skills/build-lab/SKILL.md) is the reusable "build prompt" — invoke it as `/build-lab <Lab ID>` (e.g. `/build-lab D2-T2-L03`) to draft one lab's full content from its `labs/INDEX.md` catalog entry.
- `labs/INDEX.md` tracks each lab's status (`Planned` → `Drafted` → `Reviewed`) in its Status log section.

## Project status & TODO

**Drafted so far: 2 / 80 labs** (Domain 1, Task 1):
- [x] `D1-T1-L01` — AWS SDK & CLI Fundamentals: Making Authenticated Calls
- [x] `D1-T1-L02` — Decoupling Services with Amazon SQS

**Next up — finish Domain 1, Task 1** (`labs/01-development-with-aws-services/01-applications-on-aws/`):
- [ ] `D1-T1-L03` — Fan-Out Messaging with SNS + SQS
- [ ] `D1-T1-L04` — Event-Driven Architecture with Amazon EventBridge
- [ ] `D1-T1-L05` — Building Resilient Application Code (Retries, Backoff, Circuit Breakers)
- [ ] `D1-T1-L06` — Extending APIs with API Gateway (Transformations, Validation, Status Codes)
- [ ] `D1-T1-L07` — Unit Testing Serverless Apps with AWS SAM
- [ ] `D1-T1-L08` — Streaming Data Processing with Kinesis and Lambda
- [ ] `D1-T1-L09` — Accelerating Development with Amazon Q Developer

**Then the rest of the catalog** (see [`labs/INDEX.md`](labs/INDEX.md) for full lab lists per task):
- [ ] Domain 1, Task 2 — Lambda development (`D1-T2-L01`…`L06`, 6 labs)
- [ ] Domain 1, Task 3 — Data stores (`D1-T3-L01`…`L06`, 6 labs)
- [ ] Domain 2, Task 1 — AuthN/AuthZ (`D2-T1-L01`…`L06`, 6 labs)
- [ ] Domain 2, Task 2 — Encryption (`D2-T2-L01`…`L05`, 5 labs)
- [ ] Domain 2, Task 3 — Sensitive data (`D2-T3-L01`…`L04`, 4 labs)
- [ ] Domain 3, Task 1 — Prepare artifacts (`D3-T1-L01`…`L04`, 4 labs)
- [ ] Domain 3, Task 2 — Test in dev (`D3-T2-L01`…`L05`, 5 labs)
- [ ] Domain 3, Task 3 — Automate deployment testing (`D3-T3-L01`…`L06`, 6 labs)
- [ ] Domain 3, Task 4 — CI/CD deployment (`D3-T4-L01`…`L09`, 9 labs)
- [ ] Domain 4, Task 1 — Root cause analysis (`D4-T1-L01`…`L06`, 6 labs)
- [ ] Domain 4, Task 2 — Observability (`D4-T2-L01`…`L06`, 6 labs)
- [ ] Domain 4, Task 3 — Optimization (`D4-T3-L01`…`L08`, 8 labs)

**Other open items:**
- [ ] Run each `Drafted` lab end-to-end in the KodeKloud playground and promote it to `Reviewed` in `labs/INDEX.md`'s Status log.
- [ ] Decide whether a lightweight cleanup-verification script (or checklist) is worth adding once enough labs exist, to help students confirm a playground session left no orphaned resources.
