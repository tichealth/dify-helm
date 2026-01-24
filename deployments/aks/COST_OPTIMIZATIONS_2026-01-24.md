# Cost Optimization Recommendations

Date: 2026-01-24
Region: Australia East (australiaeast)

## Dev
- Schedule nightly shutdowns or scale node count to 0 when not used.
- Keep spot pool enabled; reduce system pool VM size if workload allows.
- Reduce PostgreSQL storage if usage is low.

## Test
- Use scheduled scaling (only run during active testing windows).
- Match spot pool size to minimum required workloads.
- Review PostgreSQL size; B_Standard_B1ms is already low‑cost.

## Prod
- Consider reserved instances for AKS node pools (1‑year or 3‑year).
- Start with 2 nodes and scale to 3 when usage requires.
- Evaluate PostgreSQL Flexible Server sizing and storage; downsize if safe.
- Consider private access for PostgreSQL to reduce exposure.

## Cross‑environment
- Use Azure Cost Management budgets and alerts by env tag.
- Add Blob lifecycle rules to move old data to Cool/Archive tiers.
- Review unused public IPs and remove them.

## Notes
- Validate all changes in dev/test before prod.
- Use Infracost to quantify savings before applying.
