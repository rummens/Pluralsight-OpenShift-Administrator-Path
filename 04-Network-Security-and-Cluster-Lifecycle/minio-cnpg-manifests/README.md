# MinIO Manifests for CNPG Backups

This folder contains a small MinIO deployment for CNPG backup testing.

## What it provides

- Namespace: `minio`
- MinIO service reachable as `http://minio.minio.svc:9000`
- Persistent storage (`5Gi`) for MinIO data
- One-time Job to create bucket `globomantics-backups`
- Optional secret manifest for CNPG namespace (`globomantics-db`)

## Required credential alignment

Use the same values for:

- `secret-minio-root-creds.yaml` (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`)
- `secret-cnpg-backup-creds.yaml` (`ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`)

These should match the credentials referenced by `cnpg-cluster.yaml`.

## Quick start

Run from this folder:

```bash
oc apply -f namespace.yaml
oc apply -f secret-minio-root-creds.yaml
oc apply -f pvc-minio-data.yaml
oc apply -f deployment-minio.yaml
oc apply -f service-minio.yaml
oc rollout status deployment/minio -n minio
oc apply -f job-create-backup-bucket.yaml
oc wait --for=condition=Complete job/minio-create-globomantics-backups -n minio --timeout=180s
oc apply -f secret-cnpg-backup-creds.yaml
```

