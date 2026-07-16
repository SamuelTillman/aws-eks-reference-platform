# ADR-0006: Network architecture, centralized-egress hub-and-spoke

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** The core topology is deployed, 3 VPCs, centralized
> per-AZ NAT, the Transit Gateway hub, all attachments, and full dev/prod
> segmentation routing. Two elements below are **deferred to a follow-up
> increment** and not yet in code: **VPC Flow Logs** (§Observability) and the
> **interface endpoints** for ECR/STS/CloudWatch Logs (§Private AWS connectivity;
> gateway endpoints for S3/DynamoDB *are* deployed).

## Context

Layer 2 (EKS) needs VPCs in the workload accounts. Rather than isolated VPCs, we
build the organization network the way a production multi-account platform
actually runs it: a Transit Gateway hub with **centralized egress**, network
**segmentation**, private AWS-service connectivity, and flow-log observability
wired into the audit backbone from Layer 1. This is a reference platform, the
network is meant to *demonstrate the real pattern*, not the shortcut.

## Decision

A **centralized-egress hub-and-spoke** anchored on a Transit Gateway in
`shared-services`.

### Topology

```
                shared-services (hub)
        ┌───────────────────────────────────┐
        │  Transit Gateway                  │
        │  Egress VPC: public subnets + NAT │──▶ Internet
        └───────────────────────────────────┘
              ▲                    ▲
         TGW attach           TGW attach
              │                    │
   workloads-dev VPC       workloads-prod VPC
   (no NAT; 0.0.0.0/0 → TGW → egress)
```

- **Transit Gateway** in `shared-services`; dev, prod, and the egress VPC attach.
- **Centralized egress VPC** (`shared-services`) owns the **per-AZ NAT
  gateways**. Workload VPCs have **no NAT**, their private subnets default-route
  to the TGW, which forwards to the egress VPC's NAT. One NAT tier for the org
  (production pattern; cheaper than NAT-per-VPC at ≥3 VPCs).

### Segmentation (TGW route tables)

- **Workloads route table** (associated: dev, prod): default route
  `0.0.0.0/0 → egress VPC attachment`. **No routes between dev and prod**, they
  are isolated by design.
- **Egress route table** (associated: egress VPC): routes to the dev and prod
  CIDRs so return traffic flows back.

### Addressing (IPAM plan)

Supernet `10.0.0.0/12`, one `/16` per account, room to grow:

| Account | CIDR |
|---|---|
| `shared-services` (egress/hub) | `10.0.0.0/16` |
| `workloads-dev` | `10.1.0.0/16` |
| `workloads-prod` | `10.2.0.0/16` |
| reserved (security, future envs) | `10.3.0.0/16` … |

Each workload `/16` → 3 AZs: private `/19` per AZ (EKS pods/nodes, ~8k IPs each),
public `/24` per AZ (ALBs only). Egress VPC uses small public subnets for NAT +
private subnets for the TGW attachment.

### Private AWS connectivity

- **Gateway endpoints** (free): S3, DynamoDB in every VPC.
- **Interface endpoints**: ECR (`api` + `dkr`), STS, CloudWatch Logs in the
  workload VPCs, so EKS nodes pull images and assume roles **without** traversing
  NAT/TGW. Toggleable (`enable_interface_endpoints`) since each carries an hourly
  cost.

### Observability

**VPC Flow Logs** from every VPC → the central log archive in the `security`
account (the Layer 1 logging bucket), extending the audit backbone to the network
layer.

### EKS-readiness

Private subnets tagged `kubernetes.io/role/internal-elb=1`, public
`kubernetes.io/role/elb=1`, and `kubernetes.io/cluster/<name>=shared`. Private
subnets sized for pod density (VPC-CNI assigns pod IPs from the subnet).

### Stack & module layout

- New stack `terraform/networking` (state key `networking/terraform.tfstate`),
  cross-account via provider aliases (`shared_services`, `workloads_dev`,
  `workloads_prod`), account IDs from `org` remote state.
- Reusable `modules/vpc` (VPC, subnets, route tables, endpoints, flow logs, TGW
  attachment). The egress VPC and TGW/route-tables live in the root stack.

### Cost posture

NAT (per-AZ, centralized) and interface endpoints are the recurring costs; all
are toggleable and the whole stack is `terraform destroy`-able for teardown
between demos. HA (per-AZ NAT) is the default but can drop to single-NAT via
`nat_gateway_count`.

## Consequences

- Workload egress depends on the TGW + egress VPC path; a break there affects all
  workload internet access (the tradeoff for centralization, mitigated by per-AZ
  HA).
- dev/prod isolation is enforced in TGW route tables, not security groups, a
  clean, auditable control.
- This unblocks Layer 2 EKS: clusters drop into the workload VPCs' private
  subnets with egress, private ECR pulls, and correct tags already in place.
- Flow logs add to the `security` log bucket's volume (minor).
- Deferred: AWS Network Firewall / centralized inspection in the egress path
  (a future ADR if the platform needs L7 egress control).
