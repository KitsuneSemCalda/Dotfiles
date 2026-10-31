# License compatibility for a BSD-licensed target

Assume the target is a BSD-licensed tree such as the DragonFlyBSD kernel or FoxynBSD base. Decide per file, from that file's own header. When the target project publishes its own license policy, that policy overrides this table.

| Source license | Into the target | Notes |
| --- | --- | --- |
| BSD-2/3-Clause, MIT, ISC, 0BSD | Allowed | Keep the original copyright and license notice in derived files. |
| Dual BSD/GPL in the file header | Allowed under the BSD terms | Confirm the header grants the permissive option; a Linux `MODULE_LICENSE("Dual BSD/GPL")` line alone does not license every file in the module. |
| Apache-2.0 | Check the target policy | Permissive but adds patent and NOTICE terms; many BSD kernels avoid it in base. |
| MPL-2.0, CDDL | Separate component only | File-level copyleft: modified files stay under their license. Keep as an isolated, clearly labeled component if the policy allows it at all. |
| GPL-2.0, GPL-3.0, LGPL, AGPL | Blocked | Not upstreamable to a BSD-licensed kernel. Use a permissive source, vendor documentation, or the clean-room split. |
| No license or unclear | Blocked | Absence of a license grants no permission. |
| Firmware blobs | Separate question | Check the redistribution license; it governs shipping the blob, not the driver code. |

Linux DRM is a common mixed case: many graphics files are MIT, but neighboring helpers and core files can be GPL. Classify every file you read.
