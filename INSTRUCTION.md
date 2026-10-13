# Deploying and validating the ToDo app

## Prerequisites

- A running Kubernetes cluster (for example, kind) and `kubectl` configured to use it.
- The following files in the repository root:
  `pv.yml`, `pvc.yml`, `configmap.yml`, `secret.yml`, `deployment.yml`, `bootstrap.sh`.
- The cluster nodes must be able to pull the image `ikulyk404/todoapp:3.0.0`.

Check that the cluster is reachable:

```bash
kubectl cluster-info
kubectl get nodes
```

All nodes must be in the `Ready` state.

## 1. Deploy all resources

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The script creates the namespace `todoapp` and applies the resources in this order:

1. PersistentVolume `pv`
2. PersistentVolumeClaim `pvc`
3. ConfigMap `app-config`
4. Secret `app-secret`
5. Deployment `todoapp`

It then waits until the Deployment rollout is finished.

## 2. Validate that the app is running

### 2.1 Pod

```bash
kubectl get pods -n todoapp
```

Expected: the pod `todoapp-...` has `READY 1/1` and `STATUS Running`.

If the pod is not ready, inspect it:

```bash
kubectl describe pod -n todoapp -l app=todoapp
kubectl logs -n todoapp deploy/todoapp
```

### 2.2 Persistent storage

```bash
kubectl get pv pv
kubectl get pvc -n todoapp
```

Expected:

- `pv`: `STATUS Bound`, `CLAIM todoapp/pvc`, `RECLAIM POLICY Delete`, `ACCESS MODES RWX`, `CAPACITY 1Gi`, `STORAGECLASS standard`
- `pvc`: `STATUS Bound`, `VOLUME pv`

Check that the volume is mounted into the container:

```bash
kubectl exec -n todoapp deploy/todoapp -- ls -la /app/data
```

Expected: the directory exists and is accessible. Check that data is writable:

```bash
kubectl exec -n todoapp deploy/todoapp -- sh -c 'echo test > /app/data/check.txt && cat /app/data/check.txt'
```

Expected output: `test`.

### 2.3 Application endpoints

```bash
kubectl port-forward -n todoapp deploy/todoapp 8080:8080
```

In a second terminal:

```bash
curl -i http://localhost:8080/api/health
curl -i http://localhost:8080/api/ready
```

Expected: HTTP status `200` for both requests.

## 3. Validate that ConfigMap data is mounted as files

The ConfigMap `app-config` contains the key `PYTHONUNBUFFERED`. Every key of a ConfigMap becomes a separate file named after the key, and the value becomes the file content.

List the files:

```bash
kubectl exec -n todoapp deploy/todoapp -- ls -la /app/configs
```

Expected: a file named `PYTHONUNBUFFERED` (Kubernetes also shows the service entries `..data` and a timestamped directory, this is normal).

Read the content:

```bash
kubectl exec -n todoapp deploy/todoapp -- cat /app/configs/PYTHONUNBUFFERED
```

Expected output: `1`.

Compare with the source ConfigMap:

```bash
kubectl get configmap app-config -n todoapp -o yaml
```

The file names must match the keys under `data`, and the file contents must match the values.

Check that the mount is read-only:

```bash
kubectl exec -n todoapp deploy/todoapp -- touch /app/configs/test
```

Expected: an error `Read-only file system`.

## 4. Validate that Secret data is mounted as a file

The Secret `app-secret` contains the key `SECRET_KEY`. It is mounted as a file named `SECRET_KEY`, and the content is the already decoded value (Kubernetes decodes base64 automatically).

List the files:

```bash
kubectl exec -n todoapp deploy/todoapp -- ls -la /app/secrets
```

Expected: a file named `SECRET_KEY`.

Read the content:

```bash
kubectl exec -n todoapp deploy/todoapp -- cat /app/secrets/SECRET_KEY
```

Expected: the decoded secret value.

Compare with the value stored in the cluster:

```bash
kubectl get secret app-secret -n todoapp -o jsonpath='{.data.SECRET_KEY}' | base64 -d
```

Both outputs must be identical.

Check that the mount is read-only:

```bash
kubectl exec -n todoapp deploy/todoapp -- touch /app/secrets/test
```

Expected: an error `Read-only file system`.

## 5. Check the mounts in the Pod specification

```bash
kubectl get pod -n todoapp -l app=todoapp -o jsonpath='{.items[0].spec.containers[0].volumeMounts}'
```

Expected mount paths: `/app/data`, `/app/configs` (readOnly: true), `/app/secrets` (readOnly: true).

## 6. Cleanup

```bash
kubectl delete -f deployment.yml
kubectl delete -f pvc.yml
kubectl delete -f pv.yml
kubectl delete -f configmap.yml
kubectl delete -f secret.yml
kubectl delete namespace todoapp
```

Note: with the `Delete` reclaim policy and a `hostPath` volume, Kubernetes cannot remove the data automatically, so the PV may switch to the `Failed` status after the PVC is removed. This is expected for `hostPath`; delete the PV manually with `kubectl delete pv pv`.

## Troubleshooting

| Symptom | Likely cause | What to check |
|---|---|---|
| Pod stays `Pending` | PVC is not `Bound` | `kubectl describe pvc pvc -n todoapp`: namespace, `storageClassName`, `volumeName`, access modes and size must match the PV |
| `FailedMount` event | ConfigMap or Secret is missing | `kubectl get configmap,secret -n todoapp` |
| Pod restarts (`CrashLoopBackOff`) | Probes fail | `kubectl describe pod`: look for `Liveness probe failed`; make sure the app answers on `/api/health` and `/api/ready` |