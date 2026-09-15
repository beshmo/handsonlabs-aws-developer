---
name: build-lab
description: Generate the full markdown content for one planned lab from the labs/INDEX.md catalog, following AGENT.md's rules and header template, with AWS syntax verified via context7. Use when the user asks to build, draft, generate, or write a specific lab (e.g. "/build-lab D1-T2-L03", "build the DynamoDB streams lab", "draft D3-T4-L06").
---

# build-lab

Generates one lab file at a time for the `handsonlabs-aws-developer` DVA-C02 course, keeping every lab consistent with `AGENT.md` and in sync with `labs/INDEX.md`.

## Input

`args` should identify one lab: its Lab ID (e.g. `D2-T2-L03`), or enough of its title/slug to uniquely match a row in `labs/INDEX.md`. If it's ambiguous or missing, ask the user which Lab ID to build — do not guess or build multiple labs in one invocation.

## Workflow

1. **Read `AGENT.md`** at the repo root in full. It defines the non-negotiable constraints (self-contained, ~30 min for Purpose–Validation, KodeKloud playground limits, optional/untimed cleanup), the required header template, and the style guide. Every rule there applies to the file you're about to write.

2. **Read `labs/INDEX.md`** and find the row for the requested Lab ID. Note: title, file path (module/task folder + filename), Primary Skills, Secondary Skills, Services. If the Lab ID isn't in the catalog, stop and tell the user — don't invent a new lab without it first being added to the catalog (per AGENT.md's "How to add or generate a lab").

3. **Pull the verbatim skill text** for every primary and secondary skill ID from the matching `specs/exam/Domain_<N>_*.md` file — the header requires the exact wording, not a paraphrase.

4. **Check playground constraints** for every service the lab uses in `specs/kodekloud-aws-playground.md`. Note the specific numeric/config limits that apply (instance types, memory/timeout ceilings, region list, capacity modes, counts). These feed the header's "Playground Constraints to Respect" bullets and must shape every step you write.

5. **Resolve current docs via context7** for every AWS CLI command, SDK call, IaC snippet (SAM/CloudFormation/CDK), or console step you're about to write. Query once per distinct service/tool involved in the lab (e.g. one query for the AWS CLI SQS commands, one for the Lambda SDK client in whatever language you choose). Never write a flag or parameter from memory alone — confirm it's current.

6. **Draft the lab file** at the exact path from `labs/INDEX.md` (create parent folders if they don't exist — they should already exist from the scaffold), following the header template in `AGENT.md` exactly:
   - Header: Lab ID, title, module/task, ~30 min, primary/secondary skills with verbatim text, services (all must be in `specs/exam/In-Scope_AWS_Services.md`), region, prerequisites, playground constraints.
   - Purpose: 2-4 sentences.
   - Steps: numbered, each with a one-line rationale tied back to a listed skill.
   - Validation: a concrete way to confirm success.
   - Cleanup (Optional): explicit teardown of every resource created, in dependency order, under a `## Cleanup (Optional)` heading with a one-line note that the KodeKloud Playground auto-cleans on session end — this section doesn't count toward the ~30-minute estimate and isn't required, but always document it.
   - References: the AWS docs actually consulted via context7.

7. **Update `labs/INDEX.md`**: change this lab's status from `Planned` to `Drafted` (add a `Status` note next to its row, or update the shared status table if one exists by then).

8. **Report back**: the file path written, the Lab ID, and the skill IDs now covered (primary + secondary) — nothing else. Keep the report to a few lines.

## Guardrails

- One lab per invocation. If the user asks for a whole task or domain, build the first lab, report it, and ask whether to continue with the next one rather than silently generating all of them (each one needs the same context7 verification rigor — don't shortcut it under volume pressure).
- Never relax the ~30-minute (Purpose–Validation, excluding the optional Cleanup) or self-contained constraints to fit more into a lab. If the catalog's skill grouping for this Lab ID genuinely doesn't fit in 30 minutes once you're drafting real steps, stop and flag it to the user instead of shipping an oversized lab — the catalog entry may need to be split.
- Never use a service, instance type, memory size, timeout, or region the playground doc disallows, even if it would make for a more "complete" demonstration. Work within the sandbox.
- If context7 returns nothing useful or errors, say so to the user rather than falling back to unverified memory for that command.
