#!/bin/bash
# cleanup.sh - Repository cleanup script

set -e

cd /workspaces/t1-kernel-patches

echo "=== Cleaning up t1-kernel-patches repository ==="
echo ""

# 1. Replace README
echo "[1/4] Simplifying README..."
mv README_new.md README.md
git add README.md

# 2. Delete CONTRIBUTING.md
echo "[2/4] Removing CONTRIBUTING.md..."
rm CONTRIBUTING.md
git add -u CONTRIBUTING.md

# 3. Commit
echo "[3/4] Committing changes..."
git commit -m "refactor: streamline documentation (t2linux style)

- Simplify README from 506 to 120 lines
- Remove excessive CONTRIBUTING.md
- Keep only essential information: install, troubleshoot, legal boundaries
- Update install script for new driver paths"

# 4. Push
echo "[4/4] Pushing to origin..."
git push origin main

echo ""
echo "✓ Repository cleanup complete!"
echo "  - README simplified to t2linux style (~120 lines)"
echo "  - CONTRIBUTING.md removed"
echo "  - Changes committed and pushed"
