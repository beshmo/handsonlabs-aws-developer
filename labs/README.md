# Hands-On Labs — AWS Certified Developer (DVA-C02)

This is a self-paced hands-on lab course covering every Task and Skill in the [DVA-C02 exam guide](../specs/exam/). Labs are designed to be run in the **KodeKloud AWS Playground** — see [`specs/kodekloud-aws-playground.md`](../specs/kodekloud-aws-playground.md) for what the sandbox allows and its resource limits.

## How this course is organized

```
labs/
  01-development-with-aws-services/   Domain 1
  02-security/                        Domain 2
  03-deployment/                      Domain 3
  04-troubleshooting-and-optimization/ Domain 4
```

Each domain folder has one subfolder per exam Task, and each Task folder has a `README.md` describing what it covers. The full catalog of every lab — title, skills practiced, services used — is [`labs/INDEX.md`](INDEX.md).

## How to pick a lab

1. Open [`labs/INDEX.md`](INDEX.md) and pick a Lab ID (e.g. `D1-T2-L03`), or just work through a Task folder top to bottom.
2. Open that lab's file. Its header lists the exact exam skill IDs it practices, the AWS services it uses, and the playground constraints to keep in mind.
3. Read **Purpose** first, then follow **Steps** in order.
4. Use **Validation** to confirm you did it right.
5. **Always run Cleanup before ending your KodeKloud session.** Every lab is self-contained by design — it creates its own resources and is responsible for deleting them. Leftover resources from a previous lab can eat into another lab's playground quota (e.g. only 10 concurrent EC2 instances, 2 Kinesis streams, 1 OpenSearch domain account-wide).

## What to expect from a lab

- **~30 minutes**, including cleanup. KodeKloud sessions run out around the 1-hour mark, so labs are scoped to comfortably fit with margin — plan for two labs per session at most if you want a buffer.
- **Fully self-contained.** No lab depends on another lab's leftover resources. You can do them in any order within a domain, though the suggested order in each Task folder builds concepts progressively.
- **CLI-first.** Most labs use the AWS CLI or an SDK, since that's what the exam tests (skills 1.1.9, 2.1.3, 2.1.4). The console is used only where it's genuinely the right tool for the skill.

## Recommended order

Domains roughly build on each other: Domain 1 (core development patterns) → Domain 2 (security) → Domain 3 (deployment) → Domain 4 (troubleshooting/optimization). Within a domain, Task order follows the exam guide. That said, every lab is self-contained, so feel free to jump to whatever skill you're weakest on.

## Status

Labs are catalogued in `labs/INDEX.md` with a `Status` of `Planned`, `Drafted`, or `Reviewed`. `Planned` labs don't have content yet — see `AGENT.md` and `.claude/skills/build-lab/SKILL.md` if you're extending this course.
