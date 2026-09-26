# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A self-paced, hands-on lab course for the **AWS Certified Developer – Associate (DVA-C02)** exam, run entirely in the **KodeKloud AWS Playground** sandbox. There is no application code, build, lint, or test suite — the repo's output is Markdown lab content, generated incrementally one lab at a time.

## Source of truth and non-negotiable rules

**`AGENT.md` is the full contract for creating or editing any lab.** Read it in full before touching lab content — do not rely on this summary alone when generating a lab. Key points:

- `labs/INDEX.md` is the single source of truth for which labs exist, their status (`Planned` → `Drafted` → `Reviewed`), and their skill-coverage mapping. Any new/changed lab must be reflected there.
- `specs/exam/Domain_{1,2,3,4}_*.md` and `specs/exam/In-Scope_AWS_Services.md` bound what a lab may teach or use — never invent a skill or service outside these.
- `specs/kodekloud-aws-playground.md` bounds every resource choice (instance types, memory/timeout ceilings, regions, capacity modes, counts). Check it for every service a lab touches before writing steps.
- Every lab must be self-contained and its Purpose–Validation flow completable in ~30 minutes. Cleanup is a separate, optional, untimed final step (`## Cleanup (Optional)`) — the KodeKloud Playground auto-terminates and cleans up all resources when a session ends, so cleanup is documented as a courtesy (e.g. to free quota for another lab in the same session), not a hard requirement.
- Every lab file must follow the exact header template in `AGENT.md` (Lab ID, module/task, skills practiced with verbatim skill text, services, region, prerequisites, playground constraints) followed by Purpose → Steps → Validation → Cleanup → References.

## Mandatory use of context7

Before writing any AWS CLI command, SDK call, CDK construct, or SAM/CloudFormation snippet in a lab, resolve and query context7 for current documentation of the tool/service involved — even when the syntax seems familiar. Never guess a flag or parameter from training data. This is enforced for every lab generated via the `build-lab` skill.

## Generating a lab

Use the `build-lab` skill: `/build-lab <Lab ID>` (e.g. `/build-lab D2-T2-L03`), defined in `.claude/skills/build-lab/SKILL.md`. It:

1. Reads `AGENT.md` for the rules/template and `labs/INDEX.md` for the catalog row (title, file path, skills, services) — if the Lab ID isn't in the catalog, it stops rather than inventing a new lab.
2. Pulls verbatim skill text from the matching `specs/exam/Domain_<N>_*.md`.
3. Checks playground limits for every service involved.
4. Verifies all CLI/SDK/IaC syntax via context7.
5. Writes the lab file at the path from `labs/INDEX.md` and flips its status to `Drafted`.
6. Reports only the file path, Lab ID, and skill IDs covered.

One lab per invocation — if asked for a whole task/domain, build the first, report it, then ask before continuing. If a lab genuinely can't fit in ~30 minutes or needs a disallowed resource, stop and flag it rather than relaxing the constraints.

## Repository layout

```
labs/<module-num>-<domain-slug>/<task-num>-<task-slug>/lab-<seq>-<slug>.md
```

Lab ID shorthand: `D<domain>-T<task>-L<seq>` (e.g. `D1-T2-L03`), used in `labs/INDEX.md` and cross-references. A lab is filed once, under the single domain/task it most centrally teaches; skills it also exercises from other domains/tasks are listed as *secondary* in the header and in `labs/INDEX.md`, not duplicated into another folder.

- `AGENT.md` — operating rules and required lab template (read this in full before generating/editing labs).
- `labs/INDEX.md` — full lab catalog, status log, and the skill-coverage matrix (all 101 exam skill IDs mapped to covering labs).
- `labs/README.md` — student-facing orientation.
- `specs/exam/` — the DVA-C02 exam guide, split by domain, plus the in-scope services list.
- `specs/kodekloud-aws-playground.md` — the sandbox's allowed services, regions, and hard resource limits.
- `.claude/skills/build-lab/SKILL.md` — the reusable generation workflow behind `/build-lab`.
- `.claude/agents/builder.md` / `reviewer.md` — subagents that draft/fix a lab and that verify a `Drafted` lab against the playground; the review → fix → PR loop is described in `AGENT.md` ("Reviewing and shipping a lab").
- `scripts/aws-cli-configuration.ps1` — points the local AWS CLI at pasted CloudShell credentials (`--set-credentials`) and restores the original setup (`--restore`); used by `reviewer`.
