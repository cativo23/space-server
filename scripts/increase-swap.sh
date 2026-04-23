#!/bin/bash
# Script to increase swap from 3.4GB to 8GB
# Run with: sudo bash increase-swap.sh

set -e

echo "Current swap status:"
free -h
swapon --show

echo ""
echo "Disabling current swap..."
swapoff /swap.img

echo "Creating new 8GB swap file..."
dd if=/dev/zero of=/swap.img bs=1M count=8192 status=progress

echo "Setting permissions..."
chmod 600 /swap.img

echo "Making swap filesystem..."
mkswap /swap.img

echo "Enabling new swap..."
swapon /swap.img

echo ""
echo "New swap status:"
free -h
swapon --show

echo ""
echo "✓ Swap increased to 8GB successfully"
