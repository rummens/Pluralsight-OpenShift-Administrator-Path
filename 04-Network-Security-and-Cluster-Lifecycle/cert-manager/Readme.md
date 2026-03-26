# OpenShift Certificate Setup

Replaces OpenShift's default self-signed certificates with certs issued by an
internal CA managed by cert-manager. This covers both the Ingress wildcard
(`*.apps.<domain>`) and the API server endpoint.

## Prerequisites

- `oc` CLI logged in with cluster-admin
- OpenShift 4.13+

---

## Step 1 — Install the cert-manager Operator

Apply the OLM resources to install the cert-manager Operator from the Red Hat catalog.

```bash
oc apply -f operator/namespace.yaml
oc apply -f operator/operator.yaml
```

Wait for the operator and its operands to be ready:

```bash
oc get pods -n cert-manager-operator
oc get pods -n cert-manager
```

All pods should be in `Running` state before continuing.

---

## Step 2 — Bootstrap the Private CA

Creates a self-signed `ClusterIssuer` to bootstrap a root CA `Certificate`,
then creates a second `ClusterIssuer` backed by that root CA to sign all
real certificates.

```bash
oc apply -f config/fake-root-ca.yaml
```

Verify the CA certificate was issued:

```bash
oc get certificate -n cert-manager
oc get clusterissuer
```

Both the `Certificate` and the backing `ClusterIssuer` should show `READY=True`.

---

## Step 3 — Issue the Wildcard Certificate

Issues a wildcard cert for `*.apps.<domain>` and wires it to the
`IngressController` so all routes use it automatically.

```bash
oc apply -f config/wildcard-cert.yaml
```

Watch the certificate get issued:

```bash
oc get certificate -n openshift-ingress
```

Once `READY=True`, patch the `IngressController` to use it:

```bash
oc patch ingresscontroller default -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"defaultCertificate":{"name":"custom-certs-managed"}}}'
```

The ingress controller pods will restart automatically to pick up the new cert.

---

## Step 4 — Trust the CA on Your Machine

Export the root CA from the cluster first:

```bash
oc get secret demo-root-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > demo-root-ca.crt
```

**macOS:**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain demo-root-ca.crt
```

**Linux (Debian/Ubuntu):**

```bash
sudo cp demo-root-ca.crt /usr/local/share/ca-certificates/demo-root-ca.crt
sudo update-ca-certificates
```

**Linux (RHEL/Fedora/CentOS):**

```bash
sudo cp demo-root-ca.crt /etc/pki/ca-trust/source/anchors/demo-root-ca.crt
sudo update-ca-trust extract
```

**Windows (PowerShell as Administrator):**

```powershell
Import-Certificate -FilePath "demo-root-ca.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
```

Or via the GUI: double-click `demo-root-ca.crt` → **Install Certificate** →
**Local Machine** → **Trusted Root Certification Authorities** → Finish.

> **Firefox users (all platforms):** Firefox does not use the system trust store.
> Import `demo-root-ca.crt` manually via
> *Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import*.

---

## Verify

Open the OpenShift console URL in your browser — you should see a valid
certificate with no warnings. From the terminal:

```bash
curl -v https://console-openshift-console.apps.test.ocp.globomantics.com
```

To also replace the **API server certificate**, add a `namedCertificates`
entry to the `APIServer` cluster resource referencing a secret with the
cert-manager issued certificate.

---

## File Overview

| File | Purpose |
|---|---|
| `operator/namespace.yaml` | Namespace for the cert-manager Operator |
| `operator/operator.yaml` | OperatorGroup + Subscription (OLM install) |
| `config/fake-root-ca.yaml` | Self-signed bootstrap issuer + root CA cert + CA-backed ClusterIssuer |
| `config/wildcard-cert.yaml` | Wildcard Certificate + IngressController reference |
