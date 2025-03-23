#!/bin/bash
echo "Creating a list of branches older than 2 days (excluding the current branch)..."
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $current_branch (will be preserved)"
branches_to_delete=$(git for-each-ref --sort=committerdate refs/heads/ --format='%(refname:short) %(committerdate:unix)' | awk -v now=$(date +%s) -v twoDaysAgo=$(($(date +%s) - 2*24*60*60)) '$2 < twoDaysAgo {print $1}' | grep -v "$current_branch")
count=$(echo "$branches_to_delete" | grep -v "^$" | wc -l)
echo "Found $count branches older than 2 days to delete"
if [ $count -eq 0 ]; then echo "No branches to delete."; exit 0; fi
echo "The following branches will be deleted:"
echo "$branches_to_delete"
echo "---"
read -p "Do you want to proceed with deletion? (y/n) " -n 1 -r; echo; if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo "Operation cancelled."; exit 1; fi
echo "Deleting branches..."
for branch in $branches_to_delete; do git branch -D "$branch"; done
echo "Branch cleanup completed!"
