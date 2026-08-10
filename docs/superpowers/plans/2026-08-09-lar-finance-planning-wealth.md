# Lar Finance Planning and Wealth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend trusted historical data into budgets, forecasts, goals, debts, investments, assets and explainable household reports.

**Architecture:** Add separate planning, credit and wealth domains. Derived projections and indicators are reproducible services with formulas/tests and explicit confidence, never opaque stored scores.

**Tech Stack:** Existing Django/API stack, Flutter client, decimal/date libraries approved by ADR, golden calculation fixtures and contract tests.

## Global Constraints

- Start after ledger, cards and import coverage are reliable.
- Distinguish confirmed, recurring and estimated values.
- Never calculate missing CET/rate/valuation from insufficient data.
- Every indicator exposes formula, date range and source freshness.

---

## Task 1: Recurrences and planned cash flow

**Files:** Create `planning/models.py`, `planning/services/forecast.py`, `planning/tests/`; add API/mobile feature.

- [ ] Write failing timezone/month-end/frequency tests.
- [ ] Implement manual recurring rules and planned occurrences.
- [ ] Add suggested recurrence only as user-confirmed behavior.
- [ ] Expose confidence/source in API and UI.

## Task 2: Budgets and goals

**Files:** Add `Budget`, `Goal` models/services/tests; add API and `mobile/lib/features/planning/`.

- [ ] Test owner/household/category scopes, rollover and partial periods.
- [ ] Implement planned versus realized calculations.
- [ ] Implement goals/reserve without automatic financial advice.
- [ ] Add accessible progress views and empty/error states.

## Task 3: Loans and installments

**Files:** Create `credit/models.py`, `credit/calculations.py`, `credit/tests/`; add API/mobile feature.

- [ ] Add golden tests for approved amortization methods, decimal rounding and partial payment.
- [ ] Implement optional rate/CET/principal/schedule fields.
- [ ] Reconcile loan payments with cash transactions.
- [ ] Label calculated values as estimates when inputs are incomplete.

## Task 4: Investments and assets/liabilities

**Files:** Create `wealth/models.py`, `wealth/services.py`, `wealth/tests/`; add API/mobile feature.

- [ ] Test positions, snapshots, currencies, ownership and reference dates.
- [ ] Implement manual/imported positions and asset/liability records.
- [ ] Prevent double count between investment account balance and positions.
- [ ] Keep live market pricing behind a separate ADR/adapter.

## Task 5: Explainable reports

**Files:** Create `reporting/queries.py`, `reporting/indicators.py`, tests; add API/mobile reports.

- [ ] Write golden tests for cash flow, category, debt, reserve and net-worth reports.
- [ ] Implement formulas as named services with documented inputs.
- [ ] Return freshness/confidence and drill-down references.
- [ ] Add table alternatives for every chart.

## Task 6: Verification

- [ ] Run all domain, API and Flutter tests.
- [ ] Compare report totals to hand-calculated synthetic fixtures.
- [ ] Test month/year/timezone/currency boundaries.
- [ ] Review wording for misleading advice or certainty.
- [ ] Update Sprints 7–10 only with evidence.
