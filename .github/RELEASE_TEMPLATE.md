# MINGYINGKEJI vX.Y.Z

## Highlights

- TBD

## Upgrade Notes

- TBD

## Breaking Changes

- None.

## Docker Images

- `webb-chen/AgentSystem-api:X.Y.Z`
- `webb-chen/AgentSystem-web:X.Y.Z`
- `webb-chen/AgentSystem-sandbox:X.Y.Z`
- `webb-chen/AgentSystem-runner:X.Y.Z`

Stable releases also publish:

- `webb-chen/AgentSystem-api:X.Y`
- `webb-chen/AgentSystem-web:X.Y`
- `webb-chen/AgentSystem-sandbox:X.Y`
- `webb-chen/AgentSystem-runner:X.Y`
- `latest`
- `sha-<short-sha>`

Pre-releases publish the exact pre-release version and `sha-<short-sha>`, but
do not update `latest`.

## Migration Checklist

- [ ] `go run ./cmd/migrate check` passed.
- [ ] `go run ./cmd/migrate check -db "$MINGYINGKEJI_MIGRATION_CHECK_DSN"` passed on a fresh PostgreSQL database.
- [ ] New migrations are append-only `YYYYMMDDHHMMSS_slug.go` files.
- [ ] Existing released migrations were not edited, deleted, or reordered.
- [ ] No destructive migration operation is present without explicit maintainer review.
- [ ] Rollback behavior is documented when rollback is supported.

## Validation

- [ ] `make check-open-source`
- [ ] API targeted tests
- [ ] Runner targeted tests
- [ ] Web type check
- [ ] Docker image build

## Contributors

- TBD
