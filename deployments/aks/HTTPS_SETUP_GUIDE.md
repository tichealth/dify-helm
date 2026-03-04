# HTTPS Setup for Dify on AKS

`deploy.sh` installs nginx-ingress, cert-manager, and applies `coredns-patch.yaml` (forward to 8.8.8.8/1.1.1.1). Ingress host comes from `project_name` in terraform.tfvars (e.g. dify-prod → dify-prod.tichealth.com.au). After deploy, add an A record for that host to the LoadBalancer IP; cert-manager will issue Let's Encrypt TLS.

## Verify

```bash
kubectl get certificate -n dify
kubectl get ingress -n dify
kubectl get svc -n ingress-nginx ingress-nginx-controller   # EXTERNAL-IP for DNS
```

## Troubleshooting

- **Certificate not issuing**: Ensure DNS A record points to the nginx LoadBalancer IP and has propagated. From cluster: `kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <your-ingress-host>`.
- **CoreDNS**: Deploy uses `coredns-patch.yaml`. To reapply: `kubectl apply -f coredns-patch.yaml` then `kubectl rollout restart deployment coredns -n kube-system`.
- **Challenges**: `kubectl get challenges -n dify`; `kubectl describe certificate dify-tls -n dify`.

Certificates auto-renew ~30 days before expiry.
