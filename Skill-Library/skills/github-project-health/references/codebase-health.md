# Codebase health

Use this as a routing checklist, not a mandatory scorecard. Select checks supported by the
project's purpose, language, lifecycle, and deployment model.

## Reproducibility and onboarding

- Installation, build, test, run, and uninstall instructions match the current code.
- Declared runtime and tool versions are sufficient to reproduce the project.
- Dependencies use appropriate manifests and lockfiles; generated files are intentional.
- Examples and sample configuration work without containing real credentials.
- A new contributor can identify the entry points and validation commands.

## Correctness and maintainability

- Existing tests exercise important behavior and failure paths rather than only happy paths.
- Automation invokes the same meaningful checks documented for local development.
- Error paths fail visibly and do not produce misleading success messages.
- Resource cleanup, retries, timeouts, concurrency, and idempotency match the problem domain.
- Module boundaries and naming make responsibilities discoverable.
- Dead code, abandoned migrations, obsolete compatibility layers, and TODOs are understood.
- Similar implementations do not drift in behavior without a documented reason.

## Security and supply chain

- Secrets, private data, build artifacts, local state, and backups are excluded appropriately.
- Inputs crossing a trust boundary are validated and outputs are encoded for their context.
- Authentication and authorization checks exist at the actual enforcement boundary.
- Network listeners, container ports, file permissions, and defaults expose no unnecessary
  surface.
- Dependencies and downloads have deliberate sources and version policies; integrity is
  verified where compromise would be material.
- CI workflows pin or appropriately trust third-party actions and do not expose secrets to
  untrusted contributions.

Do not run intrusive scanners, active exploits, credential searches outside the repository,
or network probes unless the user explicitly expands the scope.

## Operations and lifecycle

- Configuration has safe defaults and actionable validation errors.
- State-changing installation, migration, deployment, backup, and restore flows are
  recoverable and avoid partial success where practical.
- Logging is useful without leaking secrets or personal data.
- Health checks observe real readiness rather than process existence alone.
- Versioning, migration, compatibility, and deprecation policies fit the audience.
- Documentation explains important operational limitations and recovery paths.

## Documentation fidelity

Compare claims with implementation rather than reviewing prose in isolation:

- documented commands and flags versus actual parsers and scripts;
- architecture diagrams versus current components and data flow;
- supported platforms and versions versus CI and manifests;
- published features versus reachable behavior;
- security or privacy claims versus configuration and code;
- release notes versus shipped artifacts.

Treat a mismatch as more important than missing polish because it can cause users to take an
incorrect action.
