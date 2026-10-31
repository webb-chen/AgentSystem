# mingyingkeji-sandbox Configuration

This document lists the supported `MINGYINGKEJI_SANDBOX_` environment variables. Keep it
in sync with `sandbox/internal/config/config.go`, `sandbox/.env.example`, and
`sandbox/.env.production.example`.

## Local Defaults

Use `sandbox/.env.example` for local development. It uses the preview runtime
backend, local service URLs, short default TTLs, and conservative file and output
limits.

## Production Defaults

Use `sandbox/.env.production.example` as the starting point for production
deployments. Production deployments must set `MINGYINGKEJI_SANDBOX_ENV=production`, a
non-empty `MINGYINGKEJI_SANDBOX_API_KEY`, and a runtime backend that enforces network
policy.

The production example uses `MINGYINGKEJI_SANDBOX_RUNTIME_BACKEND=linux-secure`. That
backend also requires `MINGYINGKEJI_SANDBOX_SECURE_ROOTFS` and
`MINGYINGKEJI_SANDBOX_BWRAP_BINARY`. When `MINGYINGKEJI_SANDBOX_DEPENDENCY_ROOTFS_DIR` is set,
the secure runtime resolves dependency profiles from child rootfs directories
named after each profile. During startup, the service also scans those
profile-specific rootfs directories for verified profile artifacts and loads
them into the dependency catalog as ready, enabled profiles.
The Docker image ships prebuilt system dependency profiles under
`MINGYINGKEJI_SANDBOX_PREBUILT_DEPENDENCY_ROOTFS_DIR`; the container entrypoint copies
or refreshes those artifacts into `MINGYINGKEJI_SANDBOX_DEPENDENCY_ROOTFS_DIR` before
the service starts. This makes system profiles such as `skill-office`
available after a sandbox image update without installing dependencies during
user requests.
When a sandbox selects a dependency profile, the secure Linux backend activates
profile-local Python and Node paths under `/opt/mingyingkeji/profiles/<profile>`.
Profile environment values are applied after request environment values so user
code cannot override the managed profile path contract. When profile-specific
rootfs directories are enabled, the backend also verifies the built profile
manifest and read-only binds `/opt/mingyingkeji/profiles/<profile>` before execution.

## Variables

| Variable | Purpose | Local default | Production guidance |
| --- | --- | --- | --- |
| `MINGYINGKEJI_SANDBOX_ADVERTISE_URL` | Internal URL advertised to peer services. | `http://localhost:2660` | Set to the internal service URL. |
| `MINGYINGKEJI_SANDBOX_API_KEY` | Optional API key for protected operator endpoints. | empty | Required in production. |
| `MINGYINGKEJI_SANDBOX_BWRAP_BINARY` | Bubblewrap binary used by the secure Linux backend. | `bwrap` | Set to the installed binary name or absolute path. |
| `MINGYINGKEJI_SANDBOX_CACHE_TTL_SECONDS` | Sandbox endpoint cache TTL. | `30` | Keep small enough for endpoint updates to propagate quickly. |
| `MINGYINGKEJI_SANDBOX_COMMAND_TIMEOUT_SECONDS` | Default command execution timeout. | `15` | Keep bounded for workflow use. |
| `MINGYINGKEJI_SANDBOX_DATABASE_URL` | PostgreSQL connection URL. | empty in `.env.example`; composed in Docker Compose. | Required for production metadata persistence. |
| `MINGYINGKEJI_SANDBOX_DATA_DIR` | Local data directory for sandbox files and metadata. | `/var/lib/mingyingkeji-sandbox` | Use persistent storage. |
| `MINGYINGKEJI_SANDBOX_DEPENDENCY_ROOTFS_DIR` | Optional parent directory for dependency-profile-specific secure rootfs directories. | empty | Set when dependency profiles are materialized as separate rootfs directories. |
| `MINGYINGKEJI_SANDBOX_DEPENDENCY_PROFILE_BUILD_TIMEOUT_SECONDS` | Maximum dependency profile build timeout. | `600` | Tune to the largest managed profile build. |
| `MINGYINGKEJI_SANDBOX_DEPENDENCY_BUILD_COMMAND` | Optional administrator worker command for materializing queued dependency builds. | empty | Set to an operator-managed builder command when automatic dependency artifacts are enabled. |
| `MINGYINGKEJI_SANDBOX_DEPENDENCY_BUILD_WORKER_ENABLED` | Enables the local background consumer for queued dependency builds when a build command and dependency rootfs directory are configured. | `true` | Disable when an external admin consumer calls the build run endpoint. |
| `MINGYINGKEJI_SANDBOX_DEPENDENCY_BUILD_WORKER_INTERVAL_SECONDS` | Poll interval for the local dependency build worker when no queued build is available. | `2` | Keep low for interactive skill preparation; raise for low-cost batch deployments. |
| `MINGYINGKEJI_SANDBOX_PREBUILT_DEPENDENCY_ROOTFS_DIR` | Read-only profile artifact directory bundled in the sandbox image and seeded into the writable dependency rootfs at container start. | `/opt/mingyingkeji/prebuilt-dependency-rootfs` | Keep image-managed and read-only. |
| `MINGYINGKEJI_SANDBOX_REQUIRED_DEPENDENCY_PROFILES` | Comma-separated dependency profiles that must be ready for `/ready` to pass. | `skill-office` in Docker examples | Set to system profiles required by built-in platform tools. |
| `MINGYINGKEJI_SANDBOX_EGRESS_PROXY_MAX_BODY_BYTES` | Maximum request body accepted and response body returned by the egress proxy. | `1048576` | Keep bounded for workflow use and auditability. |
| `MINGYINGKEJI_SANDBOX_ENV` | Runtime environment name. | `local` | Use `production` or `prod` for production. |
| `MINGYINGKEJI_SANDBOX_INTERACTIVE_TTL_SECONDS` | Interactive sandbox TTL. | `3600` | Keep bounded and align with cleanup policy. |
| `MINGYINGKEJI_SANDBOX_LITE_MAX_WORKERS` | Maximum short-code worker count. | `4` | Tune to host capacity. |
| `MINGYINGKEJI_SANDBOX_LITE_WORKER_TIMEOUT` | Short-code worker timeout in seconds. | `5` | Keep short for stateless workflow code. |
| `MINGYINGKEJI_SANDBOX_MAX_ACTIVE` | Maximum active sandboxes per worker. | `6` | Tune to host capacity. |
| `MINGYINGKEJI_SANDBOX_MAX_ACTIVE_PER_ORGANIZATION` | Optional active sandbox quota per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_ARTIFACT_BYTES_PER_ORGANIZATION` | Optional artifact byte quota per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_ARTIFACT_MANIFEST_BYTES` | Maximum total bytes represented by one artifact manifest. | `0` disabled | Set to prevent oversized artifact responses. |
| `MINGYINGKEJI_SANDBOX_MAX_ARTIFACT_MANIFEST_FILES` | Maximum files represented by one artifact manifest. | `0` disabled | Set to prevent oversized artifact responses. |
| `MINGYINGKEJI_SANDBOX_MAX_CONCURRENT_EXECUTIONS` | Optional service-wide concurrent execution limit. | `0` disabled | Set to host capacity. |
| `MINGYINGKEJI_SANDBOX_MAX_CONCURRENT_EXECUTIONS_PER_ORGANIZATION` | Optional concurrent execution limit per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_CONCURRENT_EXECUTIONS_PER_PROFILE` | Optional concurrent execution limit per command profile. | `0` disabled | Set when specific profiles are expensive. |
| `MINGYINGKEJI_SANDBOX_MAX_DEPENDENCY_PROFILES_PER_ORGANIZATION` | Optional active dependency profile limit per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_DEPENDENCY_PROFILE_SIZE_BYTES` | Maximum managed dependency profile size. | `1073741824` | Tune to artifact storage and startup budget. |
| `MINGYINGKEJI_SANDBOX_MAX_EXECUTIONS_PER_MINUTE_PER_ORGANIZATION` | Optional execution rate limit per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_FILE_SIZE_KB` | Maximum uploaded file size. | `256` | Keep aligned with API upload policy. |
| `MINGYINGKEJI_SANDBOX_MAX_NETWORK_REQUESTS_PER_MINUTE_PER_ORGANIZATION` | Optional egress proxy request rate limit per organization. | `0` disabled | Set for shared deployments that enable network egress. |
| `MINGYINGKEJI_SANDBOX_MAX_QUEUED_EXECUTIONS_PER_ORGANIZATION` | Optional queued execution limit per organization. | `0` disabled | Set to prevent queue buildup. |
| `MINGYINGKEJI_SANDBOX_MAX_WORKSPACE_BYTES` | Optional workspace byte limit per sandbox. | `0` disabled | Set for disk protection. |
| `MINGYINGKEJI_SANDBOX_MAX_WORKSPACE_BYTES_PER_ORGANIZATION` | Optional workspace byte limit per organization. | `0` disabled | Set for shared deployments. |
| `MINGYINGKEJI_SANDBOX_MAX_WORKSPACE_FILES` | Optional workspace file count limit per sandbox. | `0` disabled | Set for inode protection. |
| `MINGYINGKEJI_SANDBOX_OBSERVER_MAX_EVENTS` | Maximum retained observer events. | `10000` | Tune to storage budget. |
| `MINGYINGKEJI_SANDBOX_OBSERVER_RETENTION_DAYS` | Observer event retention by age. | `7` | Tune to audit requirements. |
| `MINGYINGKEJI_SANDBOX_OUTPUT_LIMIT_KB` | Default stdout/stderr output limit. | `64` | Keep bounded for API responses. |
| `MINGYINGKEJI_SANDBOX_PROXY_TIMEOUT_SECONDS` | Interactive proxy timeout. | `20` | Tune to interactive preview needs. |
| `MINGYINGKEJI_SANDBOX_PUBLIC_BASE_URL` | Public base URL for routed endpoints. | `http://localhost:2660` | Set to the public sandbox URL. |
| `MINGYINGKEJI_SANDBOX_QUEUE_TIMEOUT_MS` | Maximum wait time for queued executions. | `5000` | Keep short for workflow responsiveness. |
| `MINGYINGKEJI_SANDBOX_REDIS_ADDR` | Redis address for endpoint cache coordination. | `sandbox-redis:6379` | Set when Redis is available. |
| `MINGYINGKEJI_SANDBOX_REDIS_DB` | Redis database number. | `0` | Use an isolated database where needed. |
| `MINGYINGKEJI_SANDBOX_REDIS_PASSWORD` | Redis password. | empty | Set when Redis requires authentication. |
| `MINGYINGKEJI_SANDBOX_RUNTIME_BACKEND` | Runtime backend selector. | `preview` | Use `linux-secure` in production. |
| `MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_CPU_SECONDS` | Secure Linux backend CPU time limit in seconds. | `2` | Use at least `10` for the managed Office profile and tune to command profile timeouts. |
| `MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_MEMORY_BYTES` | Secure Linux backend address-space memory limit. | `268435456` | Use at least `1073741824` for Node.js and managed Office workloads. |
| `MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_OPEN_FILE_LIMIT` | Secure Linux backend open file descriptor limit. | `128` | Keep low unless a managed profile needs more descriptors. |
| `MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_PROCESS_LIMIT` | Secure Linux backend process count limit. | `64` | Keep low enough to contain fork-heavy workloads. |
| `MINGYINGKEJI_SANDBOX_SECURE_ROOTFS` | Root filesystem path for the secure Linux backend. | empty | Required when using `linux-secure`. |
| `MINGYINGKEJI_SANDBOX_SERVER_PORT` | HTTP server port. | `2660` | Set to the exposed service port. |
| `MINGYINGKEJI_SANDBOX_SESSION_TTL_SECONDS` | Session sandbox TTL. | `1800` | Keep bounded and align with cleanup policy. |
| `MINGYINGKEJI_SANDBOX_SHUTDOWN_TIMEOUT_SECONDS` | Graceful shutdown timeout. | `10` | Keep long enough for in-flight cleanup. |
| `MINGYINGKEJI_SANDBOX_WORKER_ID` | Worker identifier included in metadata and diagnostics. | `mingyingkeji-sandbox-local` | Set to a stable worker identity. |

## Validation

Run the configuration documentation gate after changing config names or
examples:

```bash
make -C sandbox check-config-docs
```
