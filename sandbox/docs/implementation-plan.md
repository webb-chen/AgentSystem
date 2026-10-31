# mingyingkeji-sandbox Implementation Plan

## 1. Purpose

This document does not describe external products. It defines only `mingyingkeji-sandbox`'s own brand language, module names, API layers, and delivery order.

The goal is to ensure that future code, documentation, configuration, image names, and deployment assets all look like a native MINGYINGKEJI service rather than a derivative of another project.

The engineering quality rules that support this goal are defined in [engineering-standards.md](./engineering-standards.md).

The detailed production hardening backlog is tracked in [production-todo.md](./production-todo.md).

## 2. Brand and Naming Rules

### 2.1 Service Identity

Use these names consistently:

- Service name: `mingyingkeji-sandbox`
- Binary name: `mingyingkeji-sandbox`
- Docker image: `webb-chen/AgentSystem-sandbox`
- Config prefix: `MINGYINGKEJI_SANDBOX_`
- Table prefix: `sandbox_`

Avoid:

- External project names
- External environment variable prefixes
- External API path naming conventions
- Public wording that frames the service as a clone or wrapper of another sandbox

### 2.2 Runtime Names

Use exactly three runtime names:

- `lite`
- `session`
- `interactive`

Do not introduce temporary names such as:

- `vendor-lite`
- `thirdparty-mode`
- `compat-vendor`

Those names blur the product boundary and weaken the brand.

### 2.3 Module Names

Use these module names:

- `compat`
- `lifecycle`
- `exec`
- `policy`
- `observer`

Meaning:

- `compat` owns the current execution compatibility path
- `lifecycle` owns create, get, delete, renew, and endpoint discovery
- `exec` owns code, command, and file execution
- `policy` owns network, dependency, resource, and quota policy
- `observer` owns logging, audit, and metrics

## 3. Project Layout

Recommended project structure:

```text
mingyingkeji-sandbox/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── implementation-plan.md
│   └── zgo-scaffold-review.md
├── cmd/
│   ├── server/
│   │   └── main.go
│   └── migrate/
│       └── main.go
├── conf/
│   └── config.example.yaml
├── internal/
│   ├── app/
│   ├── bootstrap/
│   ├── contracts/
│   ├── infra/
│   ├── wiring/
│   ├── modules/
│   │   ├── compat/
│   │   ├── lifecycle/
│   │   ├── exec/
│   │   ├── policy/
│   │   └── observer/
│   └── runtime/
│       ├── lite/
│       ├── session/
│       └── interactive/
├── pkg/
├── docker/
└── tests/
```

Notes:

- `internal/modules/*` should own API-facing business boundaries
- `internal/runtime/*` should own execution backends
- This keeps API semantics separate from runtime semantics

## 4. API Naming

### 4.1 Phase 1

V1 should expose only the minimal execution interface:

- `GET /health`
- `POST /v1/sandbox/run`
- `GET /v1/sandbox/dependencies`
- `POST /v1/sandbox/dependencies/update`

This is a compatibility layer, not the final API shape.

### 4.2 Phase 2 Lifecycle

V2 should add lifecycle APIs:

- `POST /v1/sandboxes`
- `GET /v1/sandboxes/:id`
- `DELETE /v1/sandboxes/:id`
- `POST /v1/sandboxes/:id/renew-expiration`
- `GET /v1/sandboxes/:id/endpoints/:port`

### 4.3 Phase 2 Execution Surface

- `POST /v1/exec/code`
- `POST /v1/exec/command`
- `POST /v1/files/upload`
- `POST /v1/files/upload-archive`
- `GET /v1/files/download`
- `GET /v1/files/info`
- `DELETE /v1/files`

Command execution includes bounded `stdin`, restricted `env`, `timeout_ms`, and per-request stdout/stderr caps. The first supported command profiles are:

- `code-short`
- `skill-python`
- `skill-node`

## 5. Configuration Naming

Recommended configuration keys:

```bash
MINGYINGKEJI_SANDBOX_SERVER_PORT=2660
MINGYINGKEJI_SANDBOX_LOG_LEVEL=info
MINGYINGKEJI_SANDBOX_API_KEY=

MINGYINGKEJI_SANDBOX_LITE_MAX_WORKERS=4
MINGYINGKEJI_SANDBOX_LITE_MAX_REQUESTS=50
MINGYINGKEJI_SANDBOX_LITE_WORKER_TIMEOUT=5
MINGYINGKEJI_SANDBOX_LITE_ENABLE_NETWORK=false

MINGYINGKEJI_SANDBOX_RUNTIME_DEFAULT_PROFILE=lite
MINGYINGKEJI_SANDBOX_RUNTIME_SESSION_TTL=1800
MINGYINGKEJI_SANDBOX_RUNTIME_INTERACTIVE_TTL=3600

MINGYINGKEJI_SANDBOX_DB_ENABLED=false
MINGYINGKEJI_SANDBOX_REDIS_ENABLED=false
```

Benefits:

- Easy to distinguish from other MINGYINGKEJI services
- Cleaner integration with `mingyingkeji-api`, Docker, and Kubernetes
- Clear ownership for open-source users and contributors

## 6. Phase 1 Boundary

V1 should stay small and intentional:

- One HTTP service
- One `compat` module
- One `lite` runtime
- Python and Node.js support
- Output truncation
- Timeout handling
- Request and worker limits
- API key authentication
- Health checks

V1 should not include:

- Browser runtime
- File APIs
- Lifecycle manager
- Endpoint routing
- Egress sidecars
- Dynamic dependency installation exposed to end users

## 7. Phase 2 Boundary

V2 should focus on the session sandbox:

- `session` runtime
- Sandbox lifecycle
- Code, command, and file APIs
- `workflow_run_id` binding
- Sandbox metadata
- Artifact export

This is the point where it becomes worth introducing:

- Database storage for sandbox metadata
- Redis for state, locks, or queues
- The `observer` module

## 8. Phase 3 Boundary

V3 should focus on the interactive sandbox:

- `interactive` runtime
- Endpoint exposure
- Expiration renewal
- Egress policy
- Secure runtime

That becomes the base for browser and coding agents.

## 9. How to Use `zgo`

The recommendation is not "copy the whole project". It is:

1. Keep `bootstrap`, `infra`, `contracts`, `wiring`, and `pkg`
2. Remove the default business modules
3. Create only sandbox-specific modules under `internal/modules/`
4. Do not depend on the current `make:*` generators

## 10. Delivery Recommendation

If implementation starts now, the recommended order is:

1. Build the base `mingyingkeji-sandbox` service on top of a slim `zgo` shell
2. Implement the `compat` module and `lite` runtime first
3. Make `mingyingkeji-api -> /v1/sandbox/run -> mingyingkeji-sandbox` work end to end
4. Add `lifecycle`, `exec`, `policy`, and `observer` as later stages

This path fits an open-source project better and keeps the MINGYINGKEJI brand clean from the start.

## 11. Open-Source Delivery Rules

Every public release should follow these rules:

- Public docs describe MINGYINGKEJI decisions and boundaries directly
- Compatibility should be implemented without vendor-shaped naming
- Preview code must be labeled as preview
- Production claims must be backed by tests, platform guards, and runtime enforcement
- New contributors should be able to find the quality bar in one place

That is why `engineering-standards.md` should evolve together with the codebase, not as a one-time note.
