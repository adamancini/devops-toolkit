# Bulk Tag Operations Reference

Tag-based operations for managing groups of VMs. Tags in the Proxmox API are semicolon-delimited (e.g., `"template;cloudinit"`). Use `split(";")` for exact matching to avoid partial matches.

## List VMs by Tag

**Single tag:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | {vmid, name, status, node, tags}]'
```

**Multiple tags (AND logic -- must have all):**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select((.tags // "" | split(";")) as $t | ("<TAG1>" | IN($t[])) and ("<TAG2>" | IN($t[]))) | {vmid, name, status, node, tags}]'
```

## Bulk Start by Tag

```bash
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | select(.status == "stopped") | "\(.node) \(.vmid)"')

echo "$VMS" | while read node vmid; do
  [ -z "$node" ] && continue
  echo "Starting VMID $vmid on $node..."
  curl -sk -X POST \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/status/start"
done
```

## Bulk Shutdown by Tag

```bash
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | select(.status == "running") | "\(.node) \(.vmid)"')

echo "$VMS" | while read node vmid; do
  [ -z "$node" ] && continue
  echo "Shutting down VMID $vmid on $node..."
  curl -sk -X POST \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/status/shutdown"
done
```

## Apply Tag to VMs

```bash
for vmid in <VMID1> <VMID2> <VMID3>; do
  INFO=$(curl -sk \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
    | jq -r ".data[] | select(.vmid == $vmid) | \"\(.node) \(.tags // \"\")\"")
  node=$(echo "$INFO" | awk '{print $1}')
  existing_tags=$(echo "$INFO" | cut -d' ' -f2-)
  if [ -n "$existing_tags" ]; then
    new_tags="${existing_tags};<NEW_TAG>"
  else
    new_tags="<NEW_TAG>"
  fi
  curl -sk -X PUT \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    -d "tags=$new_tags" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/config"
done
```

## Remove Tag from All VMs

```bash
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | "\(.node) \(.vmid) \(.tags)"')

echo "$VMS" | while read node vmid tags; do
  [ -z "$node" ] && continue
  new_tags=$(echo "$tags" | tr ';' '\n' | grep -v "^<TAG>$" | paste -sd ';' -)
  curl -sk -X PUT \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    -d "tags=$new_tags" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/config"
done
```

## Safety Notes

- Always preview affected VMs before executing bulk operations (dry-run first)
- For destructive bulk operations (stop, delete), confirm with the user and list all affected VMs
- `<NODE_HOST>` in bulk queries can target any cluster node -- `cluster/resources` returns cluster-wide data
