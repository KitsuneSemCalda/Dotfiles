# Decision lenses for refactoring

Choose a lens because it explains an observed problem. These are prompts for judgment, not a scorecard. Consult original sources when the exact wording or scope of a named rule matters.

## Local code quality: Clean Code and basic heuristics

- **Naming and intent:** A name should let a maintainer predict behavior. Rename when the current name causes a concrete misunderstanding; preserve project vocabulary when it is already clear.
- **Cohesion and side effects:** Group behavior that changes for the same reason. Expose consequential effects and invariants near the code that owns them. Splitting every long function can make control flow harder to follow.
- **Duplication:** Remove repeated knowledge that can diverge. Similar syntax may represent different rules and should remain separate. A shared helper is worthwhile when it has one stable meaning.
- **Simplicity and YAGNI:** Prefer the smallest design that meets known requirements. Keep extension points only for observed or credible variations. A shorter file count is not evidence of lower complexity.
- **Change locality:** Prefer a refactor when it makes a likely future change touch fewer concepts or reduces a demonstrated failure mode. Avoid cosmetic churn without such a gain.

## Object-oriented design: SOLID

Use these questions where interfaces, inheritance, or polymorphism are actually involved:

- **Single Responsibility:** Are changes requested for unrelated reasons repeatedly landing in one module? Separate the reasons for change, not every individual method.
- **Open–Closed:** Is a stable operation repeatedly modified for real new variants? Consider an extension point only after comparing it with a simple branch or table.
- **Liskov Substitution:** Can each subtype honor the caller's preconditions, postconditions, and error behavior? Fix a broken contract before adding more inheritance.
- **Interface Segregation:** Are callers forced to depend on methods they do not use or cannot implement meaningfully? Split an interface at a real client boundary.
- **Dependency Inversion:** Does high-level policy depend directly on volatile infrastructure? Invert that source dependency at the boundary when it reduces change propagation; an interface for one stable implementation may add only indirection.

## Architecture and patterns

- **Clean Architecture:** Protect important policy from volatile delivery and persistence details when those details already change independently or are likely to. Check source dependency direction and data formats across the boundary. A small application may need only clear modules; layers and ports have a maintenance cost.
- **Design patterns:** Name the recurring problem, the concrete variants, and why a direct function, conditional, table, or module is insufficient. Compare the pattern's extra types and indirection with its expected benefit. Prefer a pattern already used coherently in the codebase when it fits.
- **Encapsulation:** Place an invariant where one owner can enforce it. Do not hide data behind accessors that merely forward it or prevent legitimate operations.

## Algorithms and data structures

Define the operation mix and input dimensions: size, read/write ratio, order requirements, mutation, concurrency, memory budget, and I/O. Compare existing and proposed structures on the operations the path performs, including maintenance and conversion costs. Derive time and space from the actual calls; distinguish theoretical growth from a measured bottleneck. A new index, cache, or data structure is useful when its benefit exceeds update, invalidation, and memory costs. For a dedicated read-only complexity audit, use `algorithmic-project-review` instead.

## JPL Power of Ten

Holzmann's rules target analyzable safety-critical C. Apply them literally only when that risk profile and language justify it. In other code, transfer the relevant goal and explain the adaptation:

1. Keep control flow simple enough to reason about; do not ban useful recursion without a boundedness concern.
2. Bound loops or prove progress where unbounded execution would cause harm.
3. Control dynamic allocation after initialization where predictable memory use is required.
4. Keep functions reviewable; the original line limit is not a universal quality threshold.
5. Use meaningful assertions for invariants; do not target an assertion count.
6. Limit variable scope to where the state is needed.
7. Check inputs and results at boundaries where failure matters.
8. Constrain preprocessor use in C when it impedes analysis.
9. Limit confusing pointer indirection and preserve ownership clarity.
10. Enable relevant compiler warnings and static analysis, then investigate actionable findings.

## Primary sources and scope

- Robert C. Martin, [Clean Code](https://www.informit.com/store/clean-code-a-handbook-of-agile-software-craftsmanship-9780132350884): names, functions, design, and maintenance practices; the heuristics above are deliberately contextual rather than a restatement of its rules.
- Martin Fowler, [Refactoring](https://martinfowler.com/books/refactoring.html) and [Code Smell](https://martinfowler.com/bliki/CodeSmell.html): behavior-preserving design changes and smells as prompts for investigation.
- Robert C. Martin, [Single Responsibility Principle](https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html) and [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html): reasons for change and the dependency rule.
- Martin Fowler, [Writing Software Patterns](https://martinfowler.com/articles/writingPatterns.html): patterns as context-dependent advice.
- Gerard J. Holzmann, [The Power of Ten](https://spinroot.com/gerard/pdf/Power_of_Ten.pdf) and [experience applying the rules](https://spinroot.com/gerard/pdf/P10exp.pdf): original safety-critical C context and later clarifications.
