---
topic: macos-disk-space-snapshots
source:
  - https://www.reddit.com/r/mac/comments/12ewy4v/ive_cleaned_my_mac_countless_times_and_cant/jff87vp/
  - https://support.apple.com/en-us/102154
  - https://eclecticlight.co/2020/04/09/where-did-all-that-free-space-go-on-my-apfs-disk/
  - https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/
  - https://eclecticlight.co/2022/02/10/managing-snapshots-how-to-stop-them-eating-free-space/
created: 2026-02-24
updated: 2026-02-24
tags:
  - macos
  - disk-space
  - time-machine
  - apfs
  - troubleshooting
---

# macOS Disk Space: Time Machine Local Snapshots

## Summary

The most common cause of a Mac's disk appearing full despite extensive cleanup is APFS local snapshots created by Time Machine. When you delete files, their data blocks remain on disk if referenced by any active snapshot. This creates a gap between what `df -h` reports (actual free blocks) and what Finder shows ("available" = free + purgeable). The space is categorized as "System Data" in About This Mac. Diagnosis uses `tmutil listlocalsnapshots /`; resolution uses `tmutil deletelocalsnapshots /`.

## Key Concepts

### Why Deleted Files Don't Free Space

APFS uses copy-on-write snapshots. When Time Machine creates an hourly snapshot, it captures a point-in-time reference to all data blocks. Deleting a file after a snapshot was taken removes the directory entry but NOT the data blocks -- the snapshot still references them. Space is only reclaimed when the snapshot itself is deleted.

### Snapshot Lifecycle

- Created approximately **every hour** when Time Machine is enabled
- One snapshot retained for each of the **last 24 hours**
- One snapshot of the **last successful backup** is kept
- An additional snapshot is created **before macOS system updates**
- Snapshots **older than 24 hours** are auto-purged (usually)

### Auto-Purge Behavior

macOS automatically thins snapshots when space is low, but Apple has never published exact thresholds. Observed behavior:

- Below ~20% free: oldest snapshots begin purging
- Below ~10% or <5 GB: purging becomes aggressive
- Auto-purge is **not always reliable** -- users report "disk full" errors even when Finder shows available space

### Space Reporting Discrepancies

| Tool | What It Reports |
|------|----------------|
| `df -h` | Raw free blocks only (most conservative, no purgeable) |
| Finder (Get Info) | Free + purgeable = "Available" (most optimistic) |
| About This Mac | Color-coded breakdown; snapshots hidden in "System Data" |
| Disk Utility | Per-volume breakdown with purgeable shown separately |
| `diskutil info /` | Full APFS detail: container free, volume free, purgeable |

The "System Data" category in About This Mac is a catch-all that includes snapshot space but provides no breakdown.

### Per-Volume vs Per-Container

APFS allows multiple volumes to share a container's free space, but purgeable space is managed per-volume. macOS cannot purge snapshots from one volume to satisfy storage requests on another. Finder reports totaled purgeable space across volumes, which is misleading.

## Practical Application

### Diagnosis

```bash
# List all local snapshots
tmutil listlocalsnapshots /

# List snapshot dates only
tmutil listlocalsnapshotdates /

# Check actual free space (conservative)
df -h /

# Detailed APFS breakdown including purgeable
diskutil info /

# Full APFS container listing
diskutil apfs list
```

Note: `tmutil listlocalsnapshots` does not show sizes. Use Disk Utility GUI (View > Show APFS Snapshots) for per-snapshot sizes.

### Delete Snapshots

```bash
# Delete ALL local snapshots at once (simplest, modern macOS)
tmutil deletelocalsnapshots /

# Delete a specific snapshot by date
sudo tmutil deletelocalsnapshots 2026-02-23-080102

# Batch delete via loop
for d in $(tmutil listlocalsnapshotdates | grep "-"); do
  sudo tmutil deletelocalsnapshots "$d"
done
```

### Thin Snapshots (Free Specific Amount)

```bash
# Syntax: tmutil thinlocalsnapshots <mount> <bytes> <urgency 1-4>
# Urgency 1 = least urgent (default), 4 = most urgent (stops backups, thins largest first)

# Aggressively free 20 GB
tmutil thinlocalsnapshots / 21474836480 4

# Nuclear option: free as much as possible
sudo tmutil thinlocalsnapshots / 999999999999999 4
```

Thinning consolidates redundant data across snapshots rather than deleting entire snapshots, preserving backup access while reclaiming space.

### Disable Local Snapshots

The old `tmutil disablelocal` / `tmutil enablelocal` commands are **deprecated on High Sierra+** and return "Unrecognized verb."

Current method: Set Time Machine to manual backups:

1. System Settings > General > Time Machine > Options
2. Set Backup Frequency to "Manually"

This stops new snapshot creation and auto-deletes existing snapshots within minutes. There is no way to keep automatic backups while disabling local snapshots on modern macOS.

### Safe Mode as Nuclear Option

If snapshots or purgeable space are stubbornly not being released:

1. Boot into Safe Mode (hold Shift on Intel, or hold power > select disk > hold Shift on Apple Silicon)
2. Restart normally

This forces macOS to purge snapshots and recalculate space.

### Troubleshooting Deletion Failures

- Grant Terminal **Full Disk Access**: System Settings > Privacy & Security > Full Disk Access
- Disable automatic backups first so Time Machine doesn't create new snapshots during deletion
- Safe Mode boot (see above) if standard deletion has no effect

## Decision Points

### When to Suspect Snapshots

- Disk appears full or "System Data" is unusually large (50+ GB)
- Recently deleted large files (VMs, video, disk images) but space was not reclaimed
- `df -h` shows low free space but Finder shows much more "available"
- Application installs or updates fail with "not enough disk space"

### When Snapshots Are NOT the Problem

- Finder and `df -h` agree on low free space -- look for actual large files
- `tmutil listlocalsnapshots /` returns no snapshots
- Time Machine is not enabled

### Third-Party Snapshots

Snapshots from tools like Carbon Copy Cloner are NOT managed by macOS auto-purge, are not counted as purgeable, and can only be deleted by the creating application.

## References

- [About Time Machine local snapshots - Apple Support](https://support.apple.com/en-us/102154)
- [Where did all that free space go on my APFS disk? - Eclectic Light](https://eclecticlight.co/2020/04/09/where-did-all-that-free-space-go-on-my-apfs-disk/)
- [Finder confuses with wildly inaccurate figures - Eclectic Light](https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/)
- [Managing snapshots - Eclectic Light](https://eclecticlight.co/2022/02/10/managing-snapshots-how-to-stop-them-eating-free-space/)
- [Reclaiming drive space by thinning APFS snapshots - Der Flounder](https://derflounder.wordpress.com/2018/04/07/reclaiming-drive-space-by-thinning-apple-file-system-snapshot-backups/)
- `man tmutil` -- canonical reference for all snapshot commands
