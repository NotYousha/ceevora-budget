# Upgrades

The baseline is v1.0 (`install/01` to `05`). Put future changes here as `U<version>_<desc>.sql`, each with a
matching `rollback/R<version>_<desc>.sql`, applied in order and listed in the release notes. Every script
must be re-runnable or guarded, and must never update `BUDGET_APPROVAL_HISTORY` (it is immutable).
