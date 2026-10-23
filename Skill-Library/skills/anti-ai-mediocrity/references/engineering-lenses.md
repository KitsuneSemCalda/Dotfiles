# Engineering lenses

Apply these independently to significant decisions. The names label principles associated with
public engineering work; they are not endorsements, quotes, or substitutes for project evidence.
Use the questions that bear on the actual artifact rather than repeating every question in a report.

## Carmack: measured execution cost

Examine data flow, latency, memory movement, cache behavior, algorithmic cost, and synchronization.
What work is unnecessary? Are allocations or copies on a measured hot path? Do abstractions hide
meaningful runtime cost? Does profiling support the optimization, and does the added complexity buy
an end-to-end gain? Reject speculative micro-optimization.

## Torvalds: representation and local clarity

Examine data structures, interface size, control flow, ownership, errors, and invariants. Does poor
representation create complexity? Can a reviewer understand the behavior locally? Are error paths
explicit? Is clever code hiding a simpler structure? Prefer fixing the representation over adding
layers around it.

## DHH: useful simplicity

Examine whether architecture solves a current problem and helps ship useful behavior. Is new
infrastructure needed now? Does an abstraction reduce total complexity, including maintenance?
Are multiple services required? Reject permanent cost for an invented future requirement.

## Ritchie: small composable mechanisms

Examine whether stable primitives and transparent interfaces are sufficient. Can components be
recombined? Does a mechanism expose capabilities without imposing unnecessary policy? Could the
system be smaller while remaining capable?

## Thompson: minimal and replaceable parts

Examine what can be deleted or replaced by a smaller tool. Is a tool turning into a framework? Can
the design be understood and maintained years later? Is configuration growing faster than useful
capability? Can parts be replaced independently?

## Resolve disagreement

Do not manufacture consensus. Name the conflicting recommendations, the project constraint that
matters, measured consequences where available, and the tradeoff chosen for this project. For
example, an abstraction may reduce application code yet add measurable latency; the decision
depends on the workload and maintenance burden, not the authority of a lens.
