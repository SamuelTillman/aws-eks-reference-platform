# ADR-0013: Cluster observability with kube-prometheus-stack

**Status:** Accepted · **Date:** 2026-07

> **Implementation status:** Implemented as a GitOps component
> ([ADR-0010](0010-gitops-argocd.md)): metrics + dashboards for the cluster,
> deliberately sized cheap and ephemeral.

## Context

The cluster runs workloads and autoscales with Karpenter
([ADR-0011](0011-karpenter-autoscaling.md)), but there is no way to **see** any of
it: no metrics, no dashboards, no view of node scale-up/consolidation, pod health,
or resource pressure. A reference platform that teaches "run it right" needs the
observability layer that operators actually rely on, and it doubles as the most
demonstrable proof the platform works (watch Karpenter add a node in a Grafana
panel).

**kube-prometheus-stack**, briefly: the community Helm chart that bundles
Prometheus (metrics collection + storage + alerting rules), Grafana
(dashboards), Alertmanager (routing), and the exporters that feed them
(node-exporter per node, kube-state-metrics for object state), pre-wired with a
large set of Kubernetes dashboards and recording/alerting rules. It is the de
facto standard metrics stack for EKS.

## Decision

Deliver **kube-prometheus-stack** as an ArgoCD Application, sized for a
**cheap, ephemeral, rebuildable** cluster rather than a production SLO backend.

### 1. GitOps, one Application

`gitops/apps/observability.yaml`, the Helm chart from the prometheus-community
repo, pinned, into a `monitoring` namespace. Picked up by the app-of-apps root
like every other component. **ServerSideApply** is on: the stack ships very large
CRDs (Prometheus, Alertmanager, ...) that blow past the client-side
last-applied-annotation size limit, server-side apply is the standard fix.

### 2. Cheap and ephemeral by default

- **No persistent storage.** Prometheus and Grafana use `emptyDir`, not PVCs.
  Metrics are transient telemetry, not system-of-record; on a cluster designed to
  be torn down and rebuilt from code ([ADR-0008](0008-cicd-lifecycle-teardown-rebuild.md)),
  persisting them earns nothing and costs EBS. A real deployment would add a PVC
  (or remote-write to Amazon Managed Prometheus).
- **Short retention** (12h) and **modest resource requests/limits** on Prometheus,
  Grafana, and the operator. Enough to see the cluster, cheap to run.
- **Alertmanager off.** No paging destination on a demo platform; enable it (and
  wire SNS/Slack) when there is something to page.
- **node-exporter + kube-state-metrics stay on**, they are the actual signal.

### 3. It also exercises Karpenter

Prometheus's footprint typically will not fit on the two small system nodes
alongside ArgoCD and Karpenter, so scheduling it makes Karpenter provision a spot
node, then consolidate it away on teardown. The observability install is thus a
live end-to-end test of autoscaling, not just a dashboard.

### 4. Reaching Grafana

Same private-first posture as ArgoCD ([ADR-0010](0010-gitops-argocd.md) §4): no
public exposure, reached by `kubectl port-forward` for now (over **http**, see
[layer2-issues.md](../layer2-issues.md) #5). The built-in Grafana admin password
is a chart default, fine for a port-forward-only, private-endpoint cluster;
ingress + SSO is the same later increment as ArgoCD's.

## Consequences

- The cluster is now observable: Grafana ships with Kubernetes/compute/network
  dashboards out of the box, and Prometheus scrapes the control plane, nodes, and
  workloads.
- Cost stays near-zero at idle (ephemeral, consolidated away with the cluster);
  the always-on footprint is only while the cluster is up.
- Not production-grade retention/HA by design. The upgrade path (PVC or Amazon
  Managed Prometheus + Grafana persistence, Alertmanager routing) is a deliberate
  later step, called out so no one mistakes the cheap tier for a durable one.
- Deferred with the rest of the ingress story: public/SSO-gated Grafana, and
  alert routing.
