---
name: procedure-name
description: One-line description of what this procedure does
image_type: cloudinit | iso | qcow2 | raw | none
requires: [api, ssh]
---

# Procedure Title

## Parameters

- param_name: Description (default: value)
- param_name: Description (required)

## Prerequisites

- List any prerequisites (e.g., "ISO must be uploaded to node storage")

## Steps

1. **Step description** (API|SSH)
   ```bash
   command here
   ```
   Expected result: description

2. **Next step** (API|SSH)
   ```bash
   command here
   ```
   Expected result: description

## Cleanup

- List any cleanup actions (e.g., "Remove downloaded image from /tmp")

## Notes

- Any important caveats or variations
