# Backup the original .bash_history
cp ~/.bash_history ~/.bash_history.bak

# Count original lines
original_lines=$(wc -l < ~/.bash_history.bak)

# Remove timestamps and keep only the command part
sed -i -E 's/^[^;]*;//' ~/.bash_history

# Count new lines
new_lines=$(wc -l < ~/.bash_history)

# Calculate removed lines
removed_lines=$((original_lines - new_lines))

# Output resume
echo "Operation completed:"
echo "- Original lines: $original_lines"
echo "- Lines after cleanup: $new_lines"
echo "- Timestamp lines removed: $removed_lines"
echo "- Original file backed up as ~/.bash_history.bak"
