# Conditional analysis lenses

Select the sections that fit the project. The named sources supply vocabulary and questions; they do not certify a project or require every listed practice. Consult authoritative current guidance when a precise standard claim matters.

## Algorithms, resources, and concurrency

- Trace significant algorithms, data structures, indexes, caches, and transformations. Include lookup, update, iteration, mutation, output size, preprocessing, space retention, copies, and external I/O. Examine repeated scans, parsing, sorting, serialization, queries, and work across nested calls. Compare realistic alternatives, including constant factors and memory cost.
- For memory-sensitive systems, inspect ownership, lifetime, leaks, allocation rate, pooling, file descriptors, connections, cache locality, and fragmentation. For low-level work, inspect alignment, false sharing, atomics, memory ordering, page faults, syscalls, and worst-case execution time only when material.
- For concurrent work, inspect races, deadlocks, starvation, contention, cancellation, backpressure, boundedness, and whether parallelism improves throughput after coordination cost.
- For critical algorithms or state machines, state invariants, preconditions, postconditions, termination, safety, and liveness properties. Use stronger formal methods only when failure cost warrants them.

## Engineering and design practices

- [SWEBOK](https://www.computer.org/education/bodies-of-knowledge/software-engineering) suggests requirements, design, construction, testing, maintenance, configuration, process, quality, and economics questions. Inspect relevant evidence rather than scoring every area.
- **Clean Code:** Investigate misleading names, hidden effects, duplication, control flow, and needless mutable state. A coherent longer function may be clearer than many wrappers.
- **SOLID:** In object-oriented or modular code, check coherent responsibility, meaningful extension boundaries, behavioral substitutability, interface size, and dependency direction. Do not add interfaces for one implementation or hypothetical variants.
- **Clean Architecture:** Separate domain policy from volatile UI, persistence, frameworks, or vendors where that separation reduces actual change cost. Do not impose ceremonial layers on a small project.
- **Objects Calisthenics:** Use as optional stress tests for encapsulation, nesting, domain primitives, collections, and cohesion. Reject rules whose application obscures behavior or inflates code.
- **DDD:** Apply bounded contexts, domain language, aggregates, entities, and invariants only when substantive domain complexity exists; do not invent enterprise structure around simple CRUD.
- For public APIs and libraries, assess contracts, error semantics, compatibility, versioning, discoverability, dependency weight, and migration cost. Make correct usage easier than misuse.

## Architecture, quality, and operations

- [ISO/IEC/IEEE 42010](https://www.iso.org/standard/74393.html) helps organize stakeholders, concerns, and architecture descriptions. [ISO/IEC 25010](https://www.iso.org/standard/78176.html) and [SEI quality-attribute scenarios](https://insights.sei.cmu.edu/library/reasoning-about-software-quality-attributes/) provide vocabulary for relevant qualities. Translate qualities into observable consequences; do not use vague labels such as “low maintainability” without a change scenario.
- Inspect cyclic or hidden coupling, shared-database APIs, unstable contracts, distributed monoliths, overlarge modules, and deployment friction when present. A modular monolith can be appropriate. Do not recommend microservices to compensate for weak modularity.
- For deployed services, assess applicable [Twelve-Factor App](https://12factor.net/) concerns: codebase, dependencies, config, backing services, build/release/run, processes, port binding, concurrency, disposability, dev/prod parity, logs, and admin processes. Mark inapplicable factors instead of forcing service conventions onto libraries, desktop apps, or embedded systems.
- For production services, use [SRE concepts](https://sre.google/sre-book/service-level-objectives/) where useful: user-facing indicators and objectives, failure diagnosis, health checks, graceful shutdown, degradation, recovery, retries, backpressure, logs, metrics, and traces. Ask whether an operator can diagnose a failure without reading the whole codebase.

## Security, safety, data, and distributed behavior

- At actual trust boundaries, inspect authentication, authorization, validation, encoding, secrets, cryptography use, dependency risk, injection, traversal, unsafe deserialization, memory safety, and supply chain. Use [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) for web application controls and [NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final) for development practices when relevant. A suspected vulnerability needs a credible attack path; do not invent one from a checklist.
- Consider the [JPL Power of Ten](https://spinroot.com/gerard/pdf/Power_of_Ten.pdf) primarily for safety-critical or embedded C. Transfer bounded behavior, analyzability, assertions, checked results, and failure visibility to other domains only when justified. Do not impose C-specific rules on ordinary applications or claim safety certification.
- With persistent data, inspect schema, constraints, indexes, query plans, transactions, isolation, locking, migrations, backup, restore, retention, and ownership. For data-heavy systems also consider lineage, partitioning, replication, and conflict resolution where material.
- For distributed systems, reason about partial failure, consistency, retries, timeouts, duplicate delivery, ordering, idempotency, partitions, and clocks. Use CAP, PACELC, consensus, and queueing theory only when they clarify the actual design. Retries can duplicate effects.

## Product, cost, and emerging systems

- Inspect the path from source to installation, configuration, first result, repeated use, update, support, and removal. Identify which technical opportunities yield visible benefits such as lower latency, lower cost, stronger privacy, simpler setup, safer automation, or better portability.
- Count CPU, memory, storage, network, cloud, CI, deployment, operational labor, and developer time as costs when material. Complexity is a resource: every new service, queue, cache, thread, dependency, layer, protocol, or configuration mechanism needs a reason.
- For AI systems, examine evaluation design, nondeterminism, hallucination boundaries, prompt injection, provenance, provider coupling, fallback behavior, latency, cost per operation, and observability. Do not mistake a polished demo for measured reliability.
- Technical differentiation may come from incremental computation, efficient indexing, deterministic behavior, reproducible builds, automatic recovery, better introspection, or simpler protocols. Label these as experimental until value and feasibility are supported.
