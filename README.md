# forge-infra

> **Deprecation notice:** forge-infra is deprecated. New updates will be done on [forge-issue](https://github.com/CODEANDTRUST/forge-issue).

Factory-wide infrastructure for the **Forge software factory**.

This repo holds what is shared across the forge services (forge-issue, forge-code, forge-pr). The service code lives in its own repos; this repo holds the host-level deploy kit and factory-wide conventions.

## Layout

- `deploy/` — the host rebuild kit: path router, launchd plists for every service, OAuth keepalive probe, install README

## Services

| Repo | Role |
|---|---|
| [forge-issue](https://github.com/CODEANDTRUST/forge-issue) | Reporter intake → GitHub issue (Gleam/JS) |
| [forge-code](https://github.com/CODEANDTRUST/forge-code) | Issue → pull request develop stage (Gleam/OTP) |
| [forge-pr](https://github.com/CODEANDTRUST/forge-pr) | PR review stage (Gleam/OTP) |
| forge-infra (this repo) | Deploy kit + factory conventions |

## Trace observability

The forge trace catalog (event allowlist for the public ZenBin log) lives in `forge-issue/runtime/trace.js`. **Deploy-order rule:** emit-side changes in forge-code/forge-pr MUST update the catalog first (or same PR), then restart the sidecar. See `forge-issue/docs/trace.md`.
