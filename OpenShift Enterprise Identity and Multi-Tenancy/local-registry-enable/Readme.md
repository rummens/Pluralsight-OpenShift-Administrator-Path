The error means your OpenShift SNO's integrated image registry is in `Removed` state, which is the default on
bare-metal/SNO installs because no shared object storage is automatically provisioned. You need to enable the registry
and give it storage before your BuildConfig can push to an `ImageStreamTag`.

## Step 1: Configure Storage
The registry needs storage to operate. We already have NFS available from the `nfs-server` deployment, so we'll use that:

```bash
oc apply -f registry-pvc.yaml
```

## Step 2: Enable the Registry Operator

Change the `managementState` from `Removed` to `Managed`:[1][2]

```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge \
  --patch '{"spec":{"managementState":"Managed","storage":{"pvc":{"claim":"image-registry-storage"}}}}'
```

## Step 3: Verify the Registry is Up

```bash
oc get co image-registry
```

Wait until `AVAILABLE` shows `True` and `PROGRESSING` drops to `False`.

## Step 4: Create the ImageStream

Your BuildConfig targets `result:latest` but the `ImageStream` object itself also needs to exist:

```bash
oc create imagestream result -n private-registry-demo
```

## Step 5: Re-run the Build

```bash
oc start-build bc/buildah-build -n private-registry-demo --follow
```

***

**Optionally**, if you want the registry reachable externally (e.g. to `podman pull` from your laptop), expose the
default route:

```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --patch '{"spec":{"defaultRoute":true}}' \
  --type=merge
```
