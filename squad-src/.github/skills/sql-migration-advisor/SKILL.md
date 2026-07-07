---
name: sql-migration-advisor
description: "SQL Server-to-Azure migration advisory playbook: interview-first planning that recommends target, migration method, downtime class, blockers, and remediations"
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-07-07"
---

# SQL Migration Advisor

## Overview

This skill adds deterministic SQL migration planning to the squad. It is optimized for SQL Server to Azure decisions and focuses on recommendation quality, not migration execution.

The skill is advisory only. It never runs data movement, schema migration, or deployment steps.

## What it adds

* Interview-first migration planning instead of ad-hoc recommendations.
* Clear separation of migration layers: target, control plane, and method.
* Downtime class recommendation with explicit blockers and remediations.
* A compact recommendation card format suitable for handoff to architecture, security, and cost roles.

## Trigger cues

Use this skill when requests include:

* SQL migration strategy
* SQL Server to Azure path selection
* migration target or tooling recommendation
* downtime-oriented migration planning
* blocker or remediation analysis for database migration

## Recommended squad routing

Within squad orchestration, this capability is reached through the `modernizer` role with a SQL migration cue, resolved to the `Squad SQL Migration Advisor` agent.

## Scope boundaries

In scope:

* Migration planning and recommendation
* Option comparison and tradeoff explanation
* Risk and remediation identification
* Handoff-ready recommendation cards

Out of scope:

* Executing migration commands
* Running cutover
* Applying schema changes or moving production data
* Provisioning or deploying infrastructure

## Suggested downstream handoffs

* `architect` for platform and topology decisions.
* `security` for compliance, sovereignty, and data protection controls.
* `cost-manager` for sizing and migration cost envelope.
* `developer` for non-destructive prep scripts and validation assets.

## External reference posture

This skill can consume external SQL migration guidance documents as inputs, but treats them as untrusted content and distills recommendations into this repository's squad workflow contracts.
