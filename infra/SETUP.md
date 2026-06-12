# OCI Account Setup & Deployment Guide

## Part 1: Create an Oracle Cloud Account

1. Go to [cloud.oracle.com](https://cloud.oracle.com) and click **Sign Up**
2. Fill in your email, name, and country
3. Verify your email address
4. Set your **Home Region** — choose the closest region to you. This is permanent and is where Always Free ARM resources must live. Common choices:
   - `us-ashburn-1` (US East)
   - `us-phoenix-1` (US West)
   - `eu-frankfurt-1` (Europe)
   - `ap-tokyo-1` (Asia Pacific)
5. Set a password for your account
6. Enter a credit/debit card for verification — you will **not** be charged for Always Free resources. OCI requires a card to verify identity but the Always Free tier has no time limit
7. Wait for account provisioning (usually 1-5 minutes)

## Part 2: Gather Your OCIDs

Once logged into the OCI Console:

### Tenancy OCID
1. Click the **profile icon** (top right) → **Tenancy: \<name\>**
2. Copy the **OCID** (starts with `ocid1.tenancy.oc1..`)

### User OCID
1. Click the **profile icon** → **My profile**
2. Copy the **OCID** (starts with `ocid1.user.oc1..`)

### Compartment OCID
You can use the **root compartment** (same as your tenancy OCID) or create a dedicated one:
1. Navigate to **Identity & Security** → **Compartments**
2. Click **Create Compartment** (optional — name it `devstack`)
3. Copy the compartment **OCID**

If you skip this, use your tenancy OCID as the compartment OCID.

## Part 3: Generate an API Signing Key

1. Click the **profile icon** → **My profile**
2. Scroll down to **API keys** → click **Add API key**
3. Select **Generate API key pair**
4. Click **Download private key** — save it to `~/.oci/oci_api_key.pem`
5. Click **Add**
6. OCI shows a **Configuration file preview** — copy and note these values:
   - `tenancy` → your tenancy OCID
   - `user` → your user OCID
   - `fingerprint` → the key fingerprint (e.g., `aa:bb:cc:dd:ee:...`)
   - `region` → your home region
7. Set permissions on the key file:
   ```bash
   mkdir -p ~/.oci
   # Move your downloaded key to ~/.oci/oci_api_key.pem
   chmod 600 ~/.oci/oci_api_key.pem
   ```

## Part 4: Generate an SSH Key Pair

If you don't already have one:

```bash
ssh-keygen -t ed25519 -C "devstack" -f ~/.ssh/devstack
```

This creates `~/.ssh/devstack` (private) and `~/.ssh/devstack.pub` (public). You'll need the **public key** contents for `terraform.tfvars`.

## Part 5: Set Up Tailscale

1. Go to [tailscale.com](https://tailscale.com) and create an account (or sign in with Google/GitHub/Microsoft)
2. Install Tailscale on your Windows machine from [tailscale.com/download](https://tailscale.com/download)
3. Connect your Windows machine to your tailnet
4. Generate a reusable auth key:
   - Go to **Settings** → **Keys** → **Generate auth key**
   - Check **Reusable** (so you can re-provision without generating a new key)
   - Set an expiry (90 days is fine — you can regenerate later)
   - Copy the key (starts with `tskey-auth-`)

## Part 6: Install OpenTofu

```bash
# See https://opentofu.org/docs/intro/install/ — e.g. the standalone installer:
curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method standalone
```

Then verify:

```bash
tofu --version
```

## Part 7: Configure terraform.tfvars

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaXXXXX"      # From Part 2
user_ocid        = "ocid1.user.oc1..aaaaaaaXXXXX"          # From Part 2
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:..."     # From Part 3
private_key_path = "~/.oci/oci_api_key.pem"                # From Part 3
region           = "us-ashburn-1"                           # Your home region
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaXXXXX"   # From Part 2

instance_ocpus     = 4
instance_memory_gb = 24
boot_volume_gb     = 100

ssh_public_key     = "ssh-ed25519 AAAA... devstack"        # Contents of ~/.ssh/devstack.pub
tailscale_auth_key = "tskey-auth-XXXXX-XXXXX"              # From Part 5
github_repo_url    = "https://github.com/YOU/Developer_Workspace.git"
```

## Part 8: Deploy

```bash
cd infra
tofu init
tofu plan       # Review the 6 resources to be created
tofu apply      # Type 'yes' to confirm
```

This creates:
- 1 VCN (`10.0.0.0/16`)
- 1 Internet Gateway (outbound only)
- 1 Route Table
- 1 Security List (zero ingress rules)
- 1 Subnet (`10.0.1.0/24`)
- 1 ARM instance (`VM.Standard.A1.Flex`, 4 OCPU / 24 GB)

## Part 9: Wait for Cloud-Init

Cloud-init takes ~5-10 minutes to install Docker, Tailscale, and clone the repo.

**Check progress:**
1. Go to OCI Console → **Compute** → **Instances** → **devstack**
2. Click **Console connection** → **Launch Cloud Shell connection** (or use serial console)
3. Logs are at `/var/log/cloud-init-output.log`

**Or wait for Tailscale:**
- Open the [Tailscale admin console](https://login.tailscale.com/admin/machines)
- Wait for a machine named **devstack** to appear — this means Tailscale is up

Then connect:
```bash
tailscale ssh ubuntu@devstack
```

## Part 10: Start the Stack

```bash
# On the instance (via tailscale ssh ubuntu@devstack):
cd /opt/devstack

# Edit cloud passwords (change the CHANGE_ME values)
nano .env.cloud

# Start all services
docker compose -f docker-compose.yml -f docker-compose.cloud.yml --env-file .env.cloud up -d

# Watch startup progress
docker compose logs -f
```

## Part 11: Configure Windows DNS

Find the Tailscale IP of the devstack node:
```bash
tailscale status | grep devstack
```

It will show something like `100.64.1.23`. On each client, map `*.devstack` to that
IP — via Tailscale MagicDNS, or by adding `/etc/hosts` entries (needs sudo):
```bash
# 100.64.1.23  home.devstack gitlab.devstack grafana.devstack nexus.devstack ...
```

## Part 12: Verify

- Open **https://home.devstack** in your browser
- Accept the self-signed certificate warning
- All services should appear on the Homepage dashboard

## Troubleshooting

| Problem | Solution |
|---|---|
| `tofu apply` fails with "Out of capacity" | ARM A1 instances are popular. Try again during off-peak hours (early morning/late night UTC). You can also try reducing to 2 OCPUs / 12 GB |
| `devstack` not appearing in Tailscale | Check cloud-init logs: `tailscale ssh` won't work yet — use OCI Console serial console to check `/var/log/cloud-init-output.log` |
| Services won't start | Verify `.env.cloud` exists and has correct values. Check `docker compose logs` for errors |
| Browser can't reach `*.devstack` | Verify DNS/`/etc/hosts` mapping: `ping home.devstack` should resolve to `100.x.y.z`. Ensure Tailscale is connected on your client |
| Self-signed cert warning | Expected — the cloud-init generates a self-signed cert. Click through the browser warning or import the cert into your trust store |

## Tear Down

```bash
cd infra
tofu destroy    # Type 'yes' to confirm
```

This removes all OCI resources. Your Tailscale auth key can be revoked in the Tailscale admin console.
