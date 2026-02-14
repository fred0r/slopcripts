#!/bin/bash

# Backup the original .bash_history
cp ~/.bash_history ~/.bash_history.bak

# Remove timestamps and keep only the command part
sed -i -E 's/^[^;]*;//' ~/.bash_history

echo "Timestamps removed from .bash_history. Original file backed up as ~/.bash_history.bak"
