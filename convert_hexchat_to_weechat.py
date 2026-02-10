#!/usr/bin/env python3
"""
Convert HexChat logs to WeeChat 4.8.1 format and merge with existing WeeChat logs.

HexChat format: T <unix_timestamp> <message_with_color_codes>
WeeChat format: YYYY-MM-DD HH:MM:SS\t<prefix>\t<message>
"""

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HEXCHAT_DIR = Path("/home/fred/project/conversion/hexchat_efnet")
WEECHAT_DIR = Path("/home/fred/project/conversion/weechat_efnet")
SUBDIRS = ["1", "2", "3", "4"]


def strip_mirc_colors(text):
    """Strip mIRC color codes, bold, underline, reverse, etc."""
    # Color codes: \x03 followed by optional fg,bg numbers
    text = re.sub(r'\x03(\d{1,2}(,\d{1,2})?)?', '', text)
    # Bold, italic, underline, reverse, reset
    text = re.sub(r'[\x02\x0f\x16\x1d\x1f\x07]', '', text)
    return text


def parse_hexchat_line(line):
    """Parse a hexchat log line and return (timestamp, prefix, message) in weechat format."""
    line = line.rstrip('\n\r')
    if not line.startswith('T '):
        return None

    # Skip lines with non-printable/binary data (but allow mIRC formatting codes)
    allowed_control = set(ord(c) for c in '\x03\x02\x0f\x16\x1d\x1f\x07\t\n\r')
    if any(ord(c) < 32 and ord(c) not in allowed_control for c in line):
        return None

    # Extract timestamp
    parts = line.split(' ', 2)
    if len(parts) < 3:
        return None

    try:
        ts = int(parts[1])
    except ValueError:
        return None

    raw = parts[2]
    # Strip mIRC color codes
    clean = strip_mirc_colors(raw)

    # Convert timestamp to datetime string
    dt = datetime.fromtimestamp(ts, tz=timezone.utc)
    dt_str = dt.strftime('%Y-%m-%d %H:%M:%S')

    # Parse message type from cleaned text
    prefix, message = classify_message(clean)
    if prefix is None:
        return None

    return (ts, dt_str, prefix, message)


def classify_message(text):
    """Classify a cleaned hexchat message and return (weechat_prefix, message)."""

    # Channel/regular message: <nick>\tmessage
    m = re.match(r'^<([^>]+)>\t(.*)$', text)
    if m:
        nick = m.group(1)
        msg = m.group(2)
        return (f'<{nick}>', msg)

    # Join: -->\tnick (user@host) has joined #channel
    m = re.match(r'^-->\t(.+)$', text)
    if m:
        return ('-->', m.group(1))

    # Part/quit: <--\tnick has quit/left
    m = re.match(r'^<--\t(.+)$', text)
    if m:
        return ('<--', m.group(1))

    # Status/system: ---\tmessage (nick changes, topic, mode, disconnects, etc.)
    m = re.match(r'^---\t(.+)$', text)
    if m:
        return ('--', m.group(1))

    # Action: *\tnick action
    m = re.match(r'^\*\t(.+)$', text)
    if m:
        return (' *', m.group(1))

    # Notice from nick: -nick-\tmessage
    m = re.match(r'^-([^-]+)-\t(.+)$', text)
    if m:
        nick = m.group(1)
        msg = m.group(2)
        return ('--', f'-{nick}- {msg}')

    # Status notice: -*status-\tmessage
    m = re.match(r'^-\*status-\t(.+)$', text)
    if m:
        return ('--', f'-*status- {m.group(1)}')

    # Outgoing CTCP/message: >nick<\tmessage
    m = re.match(r'^>([^<]+)<\t(.+)$', text)
    if m:
        nick = m.group(1)
        msg = m.group(2)
        return ('--', f'>{nick}< {msg}')

    # Private message format (hexchat query): <space>nick >>\tmessage
    # Also handles: nick >>\tmessage
    m = re.match(r'^\s*(\S+)\s*>>\t(.+)$', text)
    if m:
        nick = m.group(1)
        msg = m.group(2)
        return (f'<{nick}>', msg)

    # Plugin/system output (no tab prefix pattern) - treat as system message
    # These include: "Stored key for", "FiSHLiM plugin", IP addresses, etc.
    if '\t' not in text:
        return ('--', text)

    # Fallback: treat as system message
    return ('--', text)


def hexchat_to_weechat_filename(hexchat_name):
    """Convert hexchat filename (.txt) to weechat filename (.log)."""
    # Strip .txt, add .log
    base = hexchat_name
    if base.endswith('.txt'):
        base = base[:-4]
    return base + '.log'


def parse_weechat_line(line):
    """Parse a weechat log line and return (timestamp_for_sorting, original_line)."""
    line = line.rstrip('\n\r')
    if not line:
        return None
    # Format: YYYY-MM-DD HH:MM:SS\tprefix\tmessage
    m = re.match(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\t', line)
    if m:
        dt_str = m.group(1)
        try:
            dt = datetime.strptime(dt_str, '%Y-%m-%d %H:%M:%S')
            ts = int(dt.replace(tzinfo=timezone.utc).timestamp())
            return (ts, line)
        except ValueError:
            pass
    # Lines without parseable timestamp - skip (likely corrupted data)
    return None


def process_file(hexchat_basename):
    """Process all hexchat subdirs for a given file and merge with weechat."""
    weechat_name = hexchat_to_weechat_filename(hexchat_basename)
    weechat_path = WEECHAT_DIR / weechat_name

    # Collect all entries with timestamps for sorting
    entries = []  # list of (unix_ts, formatted_line)

    # Read from all hexchat subdirs
    hex_count = 0
    for subdir in SUBDIRS:
        hexpath = HEXCHAT_DIR / subdir / hexchat_basename
        if not hexpath.exists():
            continue
        with open(hexpath, 'r', errors='replace') as f:
            for line in f:
                result = parse_hexchat_line(line)
                if result:
                    ts, dt_str, prefix, message = result
                    formatted = f'{dt_str}\t{prefix}\t{message}'
                    entries.append((ts, formatted))
                    hex_count += 1

    if hex_count == 0:
        return 0, 0, 0

    # Read existing weechat log if it exists
    weechat_count = 0
    if weechat_path.exists():
        with open(weechat_path, 'r', errors='replace') as f:
            for line in f:
                result = parse_weechat_line(line)
                if result:
                    entries.append(result)
                    weechat_count += 1

    # Sort by timestamp (stable sort preserves order for same timestamp)
    entries.sort(key=lambda x: x[0])

    # Deduplicate consecutive identical lines (same timestamp and content)
    deduped = []
    prev = None
    for entry in entries:
        if entry != prev:
            deduped.append(entry)
        prev = entry

    # Write merged output
    with open(weechat_path, 'w') as f:
        for _, line in deduped:
            f.write(line + '\n')

    return hex_count, weechat_count, len(deduped)


def main():
    # Collect all unique hexchat filenames across subdirs
    all_hexchat_files = set()
    for subdir in SUBDIRS:
        subdir_path = HEXCHAT_DIR / subdir
        if subdir_path.exists():
            for fname in os.listdir(subdir_path):
                if fname.endswith('.txt'):
                    all_hexchat_files.add(fname)

    print(f"Found {len(all_hexchat_files)} unique HexChat log files across subdirs")

    total_converted = 0
    total_merged = 0
    files_processed = 0
    files_new = 0
    files_merged = 0

    for hexfile in sorted(all_hexchat_files):
        weechat_name = hexchat_to_weechat_filename(hexfile)
        weechat_existed = (WEECHAT_DIR / weechat_name).exists()

        hex_count, weechat_count, final_count = process_file(hexfile)
        if hex_count == 0:
            continue

        files_processed += 1
        total_converted += hex_count

        if weechat_existed:
            files_merged += 1
            total_merged += weechat_count
            print(f"  Merged: {hexfile} -> {weechat_name} "
                  f"({hex_count} hexchat + {weechat_count} weechat = {final_count} total)")
        else:
            files_new += 1
            print(f"  New:    {hexfile} -> {weechat_name} ({final_count} lines)")

    print(f"\nDone!")
    print(f"  Files processed: {files_processed}")
    print(f"  New log files created: {files_new}")
    print(f"  Existing logs merged: {files_merged}")
    print(f"  HexChat lines converted: {total_converted}")
    print(f"  WeeChat lines merged: {total_merged}")


if __name__ == '__main__':
    main()
