# NFS CSI Driver for OpenShift

This guide covers the installation and configuration of the NFS CSI driver in OpenShift to consume NFS storage from any NFS server.

## Prerequisites

- OpenShift 4.x cluster
- NFS server with accessible NFS exports
- Helm 3.x installed
- Cluster admin privileges
- Network connectivity between OpenShift nodes and NFS server

## NFS Server Configuration

### Create NFS Export

Configure your NFS server with the following requirements:

1. Create an NFS export/share with a dedicated path (e.g., `/export/k8s-storage`)
2. Configure the export to allow root access (required for dynamic provisioning):
   - Enable root squashing exception or map root to root
   - This is typically configured as `no_root_squash` in `/etc/exports` on Linux systems
3. Add your OpenShift cluster node IPs or CIDR range to the allowed clients list
4. Enable NFSv4 or NFSv3 (NFSv4.1 recommended for better performance and security)
5. Ensure the NFS service is running and the export is active

Example `/etc/exports` entry for Linux NFS servers:
```
/export/k8s-storage 192.168.1.0/24(rw,sync,no_root_squash,no_subtree_check)
```

## Installation

### Step 1: Create values.yaml

Create a `values.yaml` file with the appropriate configuration. The file includes:
- Controller configuration with 2 replicas for high availability (use 1 for Single Node OpenShift)
- Node DaemonSet settings
- Resource limits
- External snapshotter configuration
- Feature gates for FSGroup policy

Adjust the controller replicas based on your cluster size and availability requirements.

### Step 2: Install the Helm Chart

```bash
# Add the Helm repository
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts

# Update repository
helm repo update

# Install with your values.yaml
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --version 4.11.0 \
  --create-namespace \
  --namespace csi-driver-nfs \
  --values values.yaml
```

### Step 3: Grant Privileged Permissions (Critical for OpenShift)

```bash
# Grant privileged SCC to the service accounts
oc adm policy add-scc-to-user privileged -z csi-nfs-node-sa -n csi-driver-nfs
oc adm policy add-scc-to-user privileged -z csi-nfs-controller-sa -n csi-driver-nfs
```

**Important**: This step is mandatory for OpenShift. Without privileged SCC, the CSI driver pods will fail to start.

### Step 4: Verify Installation

```bash
# Check if pods are running
oc get pods -n csi-driver-nfs

# Verify CSI driver registration
oc get csidrivers nfs.csi.k8s.io
```

Expected output should show controller pods and node DaemonSet pods in `Running` state.

## StorageClass Configuration

Create a StorageClass configuration file that points to your NFS server. The StorageClass defines:

- **`server`**: IP address or hostname of your NFS server
- **`share`**: The NFS export path configured on your NFS server (the path the server is sharing)
- **`subDir`**: Subdirectory pattern for dynamic provisioning (created under the share path automatically)

When a PVC is created, the CSI driver will:
1. Connect to your NFS server
2. Access the configured export path
3. Create a unique subdirectory under that path
4. Mount that specific subdirectory into the requesting pod

The subdirectory naming can use PVC metadata variables like `${pvc.metadata.namespace}` and `${pvc.metadata.name}` for automatic organization.

Apply the StorageClass:
```bash
oc apply -f storageclass.yaml
```

### Configuration Options

- **`reclaimPolicy`**: Set to `Delete` (removes data when PVC is deleted) or `Retain` (keeps data)
- **`volumeBindingMode`**: `Immediate` (provision as soon as PVC is created) or `WaitForFirstConsumer`
- **`allowVolumeExpansion`**: Set to `true` to enable volume resizing
- **`mountOptions`**: NFS mount options like `nfsvers=4.1`, `hard`, `noatime`

## Optional: VolumeSnapshotClass

If you want snapshot support, apply the VolumeSnapshotClass configuration file.

```bash
oc apply -f volumesnapshotclass.yaml
```

**Note**: The NFS CSI driver implements snapshots using tar compression, which is slower than storage-native snapshot mechanisms. Consider this when planning backup strategies.

## Testing

Test files are provided in the repository:

1. **test-pvc.yaml**: Creates a test PersistentVolumeClaim using the NFS storage class
2. **test-pod.yaml**: Creates a test pod that mounts the PVC

Apply the test files:
```bash
# Create test PVC
oc apply -f test-pvc.yaml

# Create test pod
oc apply -f test-pod.yaml
```

Verify the setup:
```bash
# Check PVC status
oc get pvc test-nfs-pvc

# Check if pod is running
oc get pod test-nfs-pod

# Test writing data
oc exec test-nfs-pod -- touch /data/test-file
oc exec test-nfs-pod -- ls -la /data
```

Check your NFS server to verify that a subdirectory was created under your export path and the test file exists.

## Troubleshooting

### Pods in CrashLoopBackOff

**Issue**: CSI driver pods fail to start with permission errors.

**Solution**: Ensure you've granted privileged SCC:
```bash
oc adm policy add-scc-to-user privileged -z csi-nfs-node-sa -n csi-driver-nfs
oc adm policy add-scc-to-user privileged -z csi-nfs-controller-sa -n csi-driver-nfs
```

### PVC Stuck in Pending

**Issue**: PVC remains in `Pending` state.

**Check**:
1. Verify NFS export is accessible from nodes:
   ```bash
   oc debug node/<node-name>
   chroot /host
   showmount -e <nfs-server-ip>
   ```

2. Check CSI driver logs:
   ```bash
   oc logs -n csi-driver-nfs -l app=csi-nfs-controller
   ```

3. Verify NFS server configuration:
   - Root access is enabled (no_root_squash)
   - OpenShift node IPs are in allowed client list
   - NFS service is running and export is active

### Mount Permission Denied

**Issue**: Pods fail to mount with permission errors.

**Solution**: 
- Ensure NFS export allows root access (no_root_squash)
- Check that the export path has appropriate permissions (typically 755 or 777)
- Verify no conflicting NFSv4 ACLs or SELinux policies on the NFS server

### Connection Timeouts

**Issue**: Unable to connect to NFS server.

**Check**:
1. Firewall rules allow NFS traffic (TCP/UDP ports 2049, 111, and portmapper/rpcbind ports)
2. Network connectivity between OpenShift nodes and NFS server
3. NFS service is running on the server
4. Use `showmount -e <nfs-server>` from OpenShift nodes to test connectivity

### Subdirectory Not Created

**Issue**: Dynamic provisioning fails because subdirectory cannot be created.

**Solution**:
- Verify the NFS export path exists on the server
- Ensure the export allows write access
- Check that root squashing is disabled (no_root_squash is set)

## Upgrading

To upgrade the CSI driver:

```bash
# Update Helm repository
helm repo update

# Upgrade the release
helm upgrade csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace csi-driver-nfs \
  --values values.yaml
```

## Uninstalling

```bash
# Remove the Helm release
helm uninstall csi-driver-nfs -n csi-driver-nfs

# Remove the namespace
oc delete namespace csi-driver-nfs

# Remove StorageClass
oc delete storageclass <your-storageclass-name>
```

**Warning**: Deleting the StorageClass will not delete existing PVs. Handle existing volumes according to their reclaim policy before uninstalling.

## Configuration Files

The following configuration files are included in this repository:

- **`values.yaml`**: Helm chart values for OpenShift deployment
- **`storageclass.yaml`**: StorageClass definition for dynamic provisioning
- **`volumesnapshotclass.yaml`**: Optional VolumeSnapshotClass for snapshot support
- **`test-pvc.yaml`**: Test PersistentVolumeClaim
- **`test-pod.yaml`**: Test pod for verification

## References

- [NFS CSI Driver GitHub](https://github.com/kubernetes-csi/csi-driver-nfs)
- [Driver Parameters Documentation](https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/docs/driver-parameters.md)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)

## Notes

- The NFS CSI driver supports `ReadWriteMany` (RWX) access mode, making it ideal for shared storage scenarios
- Multiple pods across different nodes can simultaneously access the same volume
- Volume expansion is supported when `allowVolumeExpansion: true` is set in the StorageClass
- For production use, consider using `reclaimPolicy: Retain` to prevent accidental data loss
- NFSv4.1 is recommended over NFSv3 for better performance, security, and features
- The CSI driver automatically handles mounting on nodes - no manual NFS mounts required
