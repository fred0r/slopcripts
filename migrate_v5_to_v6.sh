#!/bin/bash

################################################################################
# AMXBans v5 to v6.14.4 Database Migration Script (Bash/Shell version)
#
# This script migrates data from AMXBans v5 database to v6.14.4 schema.
#
# Usage:
#   1. Update configuration below with your database credentials
#   2. Make script executable: chmod +x migrate_v5_to_v6.sh
#   3. Run: ./migrate_v5_to_v6.sh
#   4. Or: bash migrate_v5_to_v6.sh
#
# Note: Requires mysql, mysqldump commands to be installed
################################################################################

set -e  # Exit on error

# =====================================================================
# CONFIGURATION - MODIFY THESE VALUES
# =====================================================================

# Source database (v5)
V5_HOST="127.0.0.1"
V5_USER="user"
V5_PASSWORD="pass"
V5_DB="amx5-src"
V5_PREFIX="amx_"

# Target database (v6)
V6_HOST="127.0.0.1"
V6_USER="user"
V6_PASSWORD="pass"
V6_DB="amxbans6"
V6_PREFIX="amx_"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =====================================================================
# FUNCTIONS
# =====================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build MySQL command with credentials
mysql_cmd_v5() {
    if [ -z "$V5_PASSWORD" ]; then
        mysql -h "$V5_HOST" -u "$V5_USER" "$V5_DB"
    else
        mysql -h "$V5_HOST" -u "$V5_USER" -p"$V5_PASSWORD" "$V5_DB"
    fi
}

mysql_cmd_v6() {
    if [ -z "$V6_PASSWORD" ]; then
        mysql -h "$V6_HOST" -u "$V6_USER" "$V6_DB"
    else
        mysql -h "$V6_HOST" -u "$V6_USER" -p"$V6_PASSWORD" "$V6_DB"
    fi
}

# Execute SQL query on v5 database
query_v5() {
    echo "$1" | mysql_cmd_v5 2>/dev/null
}

# Execute SQL query on v6 database
query_v6() {
    echo "$1" | mysql_cmd_v6 2>/dev/null
}

# Test database connection
test_connection() {
    local db=$1
    local host=$2
    local user=$3
    local pass=$4

    if [ "$db" = "v5" ]; then
        if [ -z "$pass" ]; then
            mysql -h "$host" -u "$user" "$V5_DB" -e "SELECT 1" >/dev/null 2>&1
        else
            mysql -h "$host" -u "$user" -p"$pass" "$V5_DB" -e "SELECT 1" >/dev/null 2>&1
        fi
    else
        if [ -z "$pass" ]; then
            mysql -h "$host" -u "$user" "$V6_DB" -e "SELECT 1" >/dev/null 2>&1
        else
            mysql -h "$host" -u "$user" -p"$pass" "$V6_DB" -e "SELECT 1" >/dev/null 2>&1
        fi
    fi
}

count_rows() {
    local table=$1
    local database=$2
    if [ "$database" = "v5" ]; then
        query_v5 "SELECT COUNT(*) FROM ${V5_PREFIX}${table};"
    else
        query_v6 "SELECT COUNT(*) FROM ${V6_PREFIX}${table};"
    fi
}

# =====================================================================
# MAIN MIGRATION LOGIC
# =====================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  AMXBans v5 to v6 Database Migration Script                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Test connections
    log_info "Testing database connections..."

    if test_connection v5 "$V5_HOST" "$V5_USER" "$V5_PASSWORD"; then
        log_success "Connected to v5 database: $V5_DB"
    else
        log_error "Cannot connect to v5 database!"
        log_error "Check: host=$V5_HOST, user=$V5_USER, db=$V5_DB"
        exit 1
    fi

    if test_connection v6 "$V6_HOST" "$V6_USER" "$V6_PASSWORD"; then
        log_success "Connected to v6 database: $V6_DB"
    else
        log_error "Cannot connect to v6 database!"
        log_error "Check: host=$V6_HOST, user=$V6_USER, db=$V6_DB"
        exit 1
    fi

    echo ""

    # Show pre-migration counts
    log_info "Checking data in v5 database..."
    v5_bans=$(count_rows "bans" "v5")
    v5_admins=$(count_rows "amxadmins" "v5")
    v5_webadmins=$(count_rows "webadmins" "v5")
    v5_reasons=$(count_rows "banreasons" "v5")

    echo "  - Bans: $v5_bans"
    echo "  - AMX Admins: $v5_admins"
    echo "  - Web Admins: $v5_webadmins"
    echo "  - Ban Reasons: $v5_reasons"
    echo ""

    # Disable foreign key checks
    log_info "Preparing for migration..."
    query_v6 "SET FOREIGN_KEY_CHECKS=0;" >/dev/null 2>&1
    log_success "Foreign key checks disabled"

    # Clear v6 tables
    log_info "Clearing existing v6 data..."
    local tables=(
        "amx_amxadmins" "amx_webadmins" "amx_levels" "amx_bans"
        "amx_bans_edit" "amx_serverinfo" "amx_reasons" "amx_admins_servers"
        "amx_logs" "amx_comments" "amx_files" "amx_flagged"
        "amx_bbcode" "amx_smilies" "amx_usermenu" "amx_modulconfig"
        "amx_webconfig" "amx_reasons_set" "amx_reasons_to_set"
    )

    for table in "${tables[@]}"; do
        query_v6 "TRUNCATE TABLE ${V6_PREFIX}${table##*_};" >/dev/null 2>&1
    done
    log_success "Tables cleared"

    echo ""

    # Migrate tables
    log_info "Migrating amx_amxadmins..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}amxadmins (id, username, password, access, flags, steamid, nickname, ashow, created, expired, days)
        SELECT id, username, password, access, flags, steamid, COALESCE(nickname, ''), 0, 0, 0, 0
        FROM \`$V5_DB\`.${V5_PREFIX}amxadmins;
    " >/dev/null 2>&1
    count=$(count_rows "amxadmins" "v6")
    log_success "  - Migrated $count admins"

    log_info "Migrating amx_webadmins..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}webadmins (id, username, password, level, logcode, email, last_action, try)
        SELECT id, username, password, CAST(level AS UNSIGNED), logcode, '', 0, 0
        FROM \`$V5_DB\`.${V5_PREFIX}webadmins;
    " >/dev/null 2>&1
    count=$(count_rows "webadmins" "v6")
    log_success "  - Migrated $count web admins"

    log_info "Migrating amx_levels..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}levels
        (level, bans_add, bans_edit, bans_delete, bans_unban, bans_import, bans_export,
         amxadmins_view, amxadmins_edit, webadmins_view, webadmins_edit,
         websettings_view, websettings_edit, permissions_edit, prune_db, servers_edit, ip_view)
        SELECT level, bans_add, bans_edit, bans_delete, bans_unban, bans_import, bans_export,
               amxadmins_view, amxadmins_edit, webadmins_view, webadmins_edit,
               'no', 'no', permissions_edit, prune_db, servers_edit, ip_view
        FROM \`$V5_DB\`.${V5_PREFIX}levels;
    " >/dev/null 2>&1
    count=$(count_rows "levels" "v6")
    log_success "  - Migrated $count permission levels"

    log_info "Migrating amx_bans..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}bans
        (bid, player_ip, player_id, player_nick, admin_ip, admin_id, admin_nick,
         ban_type, ban_reason, ban_created, ban_length, server_ip, server_name,
         ban_kicks, expired, imported)
        SELECT bid, player_ip, player_id, COALESCE(player_nick, 'Unknown'),
               admin_ip, admin_id, COALESCE(admin_nick, 'Unknown'),
               COALESCE(ban_type, 'S'), COALESCE(ban_reason, ''),
               COALESCE(ban_created, 0),
               CASE
                   WHEN ban_length = '' OR ban_length = '0' OR LOWER(ban_length) = 'permanent' THEN 0
                   WHEN ban_length REGEXP '^[0-9]+\$' THEN CAST(ban_length AS UNSIGNED) * 60
                   ELSE 0
               END,
               COALESCE(server_ip, ''), COALESCE(server_name, 'Unknown'),
               0, 0, 1
        FROM \`$V5_DB\`.${V5_PREFIX}bans;
    " >/dev/null 2>&1
    count=$(count_rows "bans" "v6")
    log_success "  - Migrated $count bans"

    log_info "Migrating ban history to bans_edit..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}bans_edit (bid, edit_time, admin_nick, edit_reason)
        SELECT bhid, COALESCE(unban_created, 0), COALESCE(unban_admin_nick, 'Unknown'),
               COALESCE(unban_reason, 'tempban expired')
        FROM \`$V5_DB\`.${V5_PREFIX}banhistory
        WHERE bhid > 0;
    " >/dev/null 2>&1
    count=$(count_rows "bans_edit" "v6")
    log_success "  - Migrated $count ban edits"

    log_info "Migrating amx_serverinfo..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}serverinfo
        (id, timestamp, hostname, address, gametype, rcon, amxban_version,
         amxban_motd, motd_delay, amxban_menu, reasons, timezone_fixx)
        SELECT id, CAST(COALESCE(timestamp, 0) AS UNSIGNED), COALESCE(hostname, 'Unknown'),
               COALESCE(address, ''), COALESCE(gametype, ''), COALESCE(rcon, ''),
               COALESCE(amxban_version, ''), COALESCE(amxban_motd, ''),
               COALESCE(motd_delay, 10), COALESCE(amxban_menu, 0), NULL, 0
        FROM \`$V5_DB\`.${V5_PREFIX}serverinfo;
    " >/dev/null 2>&1
    count=$(count_rows "serverinfo" "v6")
    log_success "  - Migrated $count server configurations"

    log_info "Migrating ban reasons..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}reasons (id, reason, static_bantime)
        SELECT id, COALESCE(reason, ''), 0
        FROM \`$V5_DB\`.${V5_PREFIX}banreasons;
    " >/dev/null 2>&1
    count=$(count_rows "reasons" "v6")
    log_success "  - Migrated $count ban reasons"

    log_info "Migrating admin-server associations..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}admins_servers (admin_id, server_id, custom_flags, use_static_bantime)
        SELECT admin_id, server_id, '', 'yes'
        FROM \`$V5_DB\`.${V5_PREFIX}admins_servers;
    " >/dev/null 2>&1
    count=$(count_rows "admins_servers" "v6")
    log_success "  - Migrated $count associations"

    log_info "Creating default web configuration..."
    query_v6 "
        INSERT INTO ${V6_PREFIX}webconfig
        (cookie, bans_per_page, design, banner, banner_url, default_lang,
         start_page, show_comment_count, show_demo_count, show_kick_count,
         demo_all, comment_all, use_capture, max_file_size, file_type,
         auto_prune, max_offences, max_offences_reason, use_demo, use_comment)
        SELECT 'amxbans', 10, 'default', '', '', 'english', 'ban_list.php',
               1, 1, 1, 0, 0, 1, 2, 'dem,zip,rar,jpg,gif', 0, 10,
               'max offences reached', 1, 1
        WHERE NOT EXISTS (SELECT 1 FROM ${V6_PREFIX}webconfig);
    " >/dev/null 2>&1
    log_success "  - Created default configuration"

    # Re-enable foreign key checks
    query_v6 "SET FOREIGN_KEY_CHECKS=1;" >/dev/null 2>&1

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Migration Completed Successfully!                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Show post-migration counts
    log_info "Final record counts in v6:"
    v6_bans=$(count_rows "bans" "v6")
    v6_admins=$(count_rows "amxadmins" "v6")
    v6_webadmins=$(count_rows "webadmins" "v6")
    v6_reasons=$(count_rows "reasons" "v6")

    echo "  - Bans: $v6_bans (v5: $v5_bans)"
    echo "  - AMX Admins: $v6_admins (v5: $v5_admins)"
    echo "  - Web Admins: $v6_webadmins (v5: $v5_webadmins)"
    echo "  - Ban Reasons: $v6_reasons (v5: $v5_reasons)"
    echo ""

    log_success "Data migration complete"
    echo ""
    log_info "Next steps:"
    echo "  1. Verify all data was migrated correctly"
    echo "  2. Run setup.php in the v6 web directory"
    echo "  3. Test the web interface"
    echo "  4. Update game server configurations"
    echo ""
}

# Run main function
main
