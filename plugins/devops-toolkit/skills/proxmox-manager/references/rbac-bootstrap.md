# RBAC Bootstrap Reference

First-time credential setup for Proxmox API access. Requires SSH access to one Proxmox node. Substitute `<SSH_USER>`, `<NODE_HOST>`, and `<PASS_PATH>` from `cluster-config.yaml`.

## Bootstrap Procedure

```bash
# 1. Create PVE-realm service account
ssh <SSH_USER>@<NODE_HOST> 'pveum user add <PVE_USER>@pve'

# 2. Create custom role with scoped privileges
ssh <SSH_USER>@<NODE_HOST> 'pveum role add <ROLE_NAME> --privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType \
   VM.PowerMgmt VM.Console VM.Migrate VM.Snapshot VM.Snapshot.Rollback \
   VM.Backup VM.Audit VM.GuestAgent.Audit \
   Datastore.Allocate Datastore.AllocateSpace Datastore.Audit \
   SDN.Use Sys.Audit Sys.Console"'

# 3. Assign permissions at cluster root
ssh <SSH_USER>@<NODE_HOST> 'pveum acl modify / --user <PVE_USER>@pve --role <ROLE_NAME>'

# 4. Create API token -- secret piped directly into pass, never displayed
ssh <SSH_USER>@<NODE_HOST> 'pveum user token add <PVE_USER>@pve <TOKEN_NAME> --privsep 0 --output-format json' \
  | jq -r '"<PVE_USER>@pve!<TOKEN_NAME>\n" + .value' \
  | pass insert -m <PASS_PATH>

# 5. Verify token works
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
```

Expected final output: `200`

## Excluded Privileges (by design)

- `Sys.Modify`, `Sys.PowerMgmt` -- cannot modify host configs or reboot nodes
- `Permissions.Modify` -- cannot escalate privileges
- `User.Modify` -- cannot create/modify users
- `Realm.*` -- cannot change authentication settings
