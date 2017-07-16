#!/bin/bash

function help() {
	echo -e "Arguments:
$0 <target> <mode> ...
target\t - host: one, comma separated or 'all'
mode:
- Backup creation:
  create <type> [taskonly]
    type\t - type of backup: (system|mysql).
    taskonly\t - create only tasks.
  
- Manipulate tasks:
  task <operation>
    list\t - list tasks, except finished tasks.
  "
}

function get_opt() {
	echo "$($DB_QUERY "SELECT \`value\` FROM \`options\` WHERE \`name\` = '$1';")"
}

function log() {
	echo -e "[$(date +'%Y-%m-%d %H:%M')][MSG] $@" | tee -a "${log_dir}/backup_$(date +'%Y-%m-%d').log"
}

function get_hosts() {
    [[ ! "$1" ]] && log "Need specify target hosts." && exit 1
    local input_targets="$(echo $1 | tr -d '[:space:]' | sed 's/,/ /g')"
    if [[ "$input_targets" == "all" ]]; then
        local input_targets=$($DB_QUERY "SELECT \`name\` FROM \`hosts\`;")
    fi
    for target in $input_targets; do
        local dbhost="$($DB_QUERY "SELECT \`name\`, \`id\` FROM \`hosts\` WHERE \`name\` = '$target';")"
        if [[ -n "$dbhost" ]]; then
            local hostname=`echo "$dbhost" | cut -d$'\t' -f1`
            local hostid=`echo "$dbhost" | cut -d$'\t' -f2`
            HOSTLIST+=(["$hostname"]="$hostid")
        else
            log "Host '$target' not found in database."
        fi
    done
}

function check_backupdb() {
	local mysql_path=$(which mysql)
	[[ ! -f "$mysql_path" ]] && log "MySQL not found!" && exit 1
    [[ ! "$DB_HOST" ]] && log 'Variable $DB_HOST is not defined!' && exit 1
    [[ ! "$DB_NAME" ]] && log 'Variable $DB_NAME is not defined!' && exit 1
    [[ ! "$DB_USER" ]] && log 'Variable $DB_USER is not defined!' && exit 1
    [[ ! "$DB_PASS" ]] && log 'Variable $DB_PASS is not defined!' && exit 1
	DB_QUERY="$mysql_path -NB -h$DB_HOST -D$DB_NAME -u$DB_USER -p$DB_PASS -e "
	local dbtest=$($DB_QUERY "SHOW TABLES;")
	if [[ ! "$?" -eq "0" ]] && [[ -z "$dbtest" ]]; then
        log "Database connection error or database is broken!"
        exit 1
    fi
}

function ssh_check() {
	SSH_PATH="$(get_opt 'ssh_path')"
	[[ ! -f "$SSH_PATH" ]] && log "SSH not found." && exit 1
}

function ssh_agent() {
    local sshagent_path="$(get_opt 'sshagent_path')"
    local sshkey_path="$(get_opt 'sshkey_path')"
    [[ ! -f "$sshagent_path" ]] && echo 'SSH AGENT not found.' && exit 1
    [[ ! -f "$sshkey_path" ]] && echo 'SSH PRIVATE KEY not found.' && exit 1
    eval $($sshagent_path)
    ssh-add $sshkey_path
}

function args_logic() {
    # $2 - mode
	case "$2" in
		create)
		# $3 - type
		# $4 - taskonly
        if [[ "$3" =~ ^(system|mysql)$ ]]; then
            task_create "$3"
            [[ ! "$4" == "taskonly" ]] && ssh_agent; task_runner || log "Create task only."
        else
            log "You need specify a correct backup type."
            exit 1
        fi
        ;;
		task)
		# $3 - operation
        case "$3" in
            list)
                task_list
            ;;
            *)
            log "You need specify a correct task operation."
            exit 1
            ;;
        esac
        ;;
		list)
        args_mode_list "$@"
        ;;
		summary)
        args_mode_summary "$@"
        ;;
		*)
        log "Need specify working mode."
        exit 1
        ;;
	esac
}

function task_create() {
	for HOST in "${!HOSTLIST[@]}"; do
        log "Creating '$1' task for host: $HOST (Task: #${HOSTLIST[$HOST]})"
        creation_date=$(date +'%Y-%m-%d %H:%M:%S')
        $DB_QUERY "INSERT INTO \`tasks\` (\`id\`,\`hostid\`,\`backup_type\`,\`date_created\`,\`date_start\`,\`date_stop\`, \`status\`) VALUES (NULL, '${HOSTLIST[$HOST]}', '$1', '$creation_date', '0000-00-00 00:00:00', '0000-00-00 00:00:00', 'todo');"
        local taskid=$($DB_QUERY "SELECT \`id\` FROM \`tasks\` WHERE id=(SELECT MAX(id) FROM \`tasks\`);")
        log "Task #$taskid has been created."
        TASKS+="$taskid "
	done
}

function task_list() {
    hostids=$(echo "${HOSTLIST[@]}" | tr ' ' ',')
    echo -e "TaskID\tHostID\tHost\tType\tCreate time\t\tStart time\t\tStop time\t\tStatus"
    printf "%0.s-" {1..115}; echo
    $DB_QUERY "SELECT tasks.id, tasks.hostid, hosts.name, tasks.backup_type, tasks.date_created, tasks.date_start, tasks.date_stop, tasks.status FROM tasks LEFT JOIN hosts ON tasks.hostid = hosts.id WHERE tasks.hostid IN ($hostids) AND tasks.status != 'finished' ORDER BY id ASC;"
}

function task_runner() {
    for task in $TASKS; do
        local task_info=$($DB_QUERY "SELECT \`hostid\`,\`backup_type\` FROM \`tasks\` WHERE \`id\` = '$task' AND \`status\` = 'todo';")
        local hostid=$(echo "$task_info" | cut -d$'\t' -f1)
        local backup_type=$(echo "$task_info" | cut -d$'\t' -f2)
        case "$backup_type" in
            system)
                backup_system $hostid $task &
            ;;
            mysql)
                backup_mysql $hostid $task &
            ;;
        esac
    done
}

function task_update() {
	local task=$1
	local state=$2
	local period=$3
	local date=$(date +'%Y-%m-%d %H:%M:%S')

	case $state in
		todo|running|finished|failed)
            $DB_QUERY "UPDATE \`tasks\` SET \`status\` = '$state' WHERE \`id\` = '$task';"
		;;
		*)
            $DB_QUERY "UPDATE \`tasks\` SET \`status\` = 'undef' WHERE \`id\` = '$task';"
		;;
	esac
	
	case $period in
		create)
            $DB_QUERY "UPDATE \`tasks\` SET \`date_created\` = '$date' WHERE \`id\` = '$task';"
		;;
		start)
            $DB_QUERY "UPDATE \`tasks\` SET \`date_start\` = '$date' WHERE \`id\` = '$task';"
		;;
		end)
            $DB_QUERY "UPDATE \`tasks\` SET \`date_stop\` = '$date' WHERE \`id\` = '$task';"
		;;
	esac
}

function backup_hostinfo() {
    local host_info=$($DB_QUERY "SELECT \`name\`, \`src_host\`, \`src_user\`, \`src_port\`, \`dst_host\`, \`dst_port\`, \`dst_user\`, \`dst_path\`, \`dst_rsync\`, \`dst_ssh\`, \`rsync_excludes\` FROM \`hosts\` WHERE \`id\` = '$1';")
    
    HOSTINFO['src_name']=$(echo "$host_info" | cut -d$'\t' -f1)
    HOSTINFO['src_host']=$(echo "$host_info" | cut -d$'\t' -f2)
    HOSTINFO['src_excld']=$(echo "$host_info" | cut -d$'\t' -f11)
    
    HOSTINFO['src_user']=$(echo "$host_info" | cut -d$'\t' -f3)
    [[ -z "${HOSTINFO['src_user']}" ]] && HOSTINFO['src_user']="$(get_opt 'default_src_user')"
    HOSTINFO['src_port']=$(echo "$host_info" | cut -d$'\t' -f4)
    [[ -z "${HOSTINFO['src_port']}" ]] && HOSTINFO['src_port']="$(get_opt 'default_src_port')"
    HOSTINFO['dst_host']=$(echo "$host_info" | cut -d$'\t' -f5)
    [[ -z "${HOSTINFO['dst_host']}" ]] && HOSTINFO['dst_host']="$(get_opt 'default_backup_host')"
    HOSTINFO['dst_port']=$(echo "$host_info" | cut -d$'\t' -f6)
    [[ -z "${HOSTINFO['dst_port']}" ]] && HOSTINFO['dst_port']="$(get_opt 'default_backup_port')"
    HOSTINFO['dst_user']=$(echo "$host_info" | cut -d$'\t' -f7)
    [[ -z "${HOSTINFO['dst_user']}" ]] && HOSTINFO['dst_user']="$(get_opt 'default_backup_user')"
    HOSTINFO['dst_path']=$(echo "$host_info" | cut -d$'\t' -f8)
    [[ -z "${HOSTINFO['dst_path']}" ]] && HOSTINFO['dst_path']="$(get_opt 'default_backup_path')"
    HOSTINFO['dst_rsync']=$(echo "$host_info" | cut -d$'\t' -f9)
    [[ -z "${HOSTINFO['dst_rsync']}" ]] && HOSTINFO['dst_rsync']="$(get_opt 'default_backup_rsync')"
    HOSTINFO['dst_ssh']=$(echo "$host_info" | cut -d$'\t' -f10)
    [[ -z "${HOSTINFO['dst_ssh']}" ]] && HOSTINFO['dst_ssh']="$(get_opt 'default_backup_ssh')"
}

function backup_mysql() {
    local hostid=$1
    local taskid=$2
	task_update $taskid running start
	backup_hostinfo $hostid
	
	local dblist=$($DB_QUERY "SELECT \`name\` FROM \`dbs\` WHERE \`hostid\` = '$hostid';")
	local dump_stor="/var/backup/mysql/"
	local backup_stor="${HOSTINFO['dst_path']}/${HOSTINFO['src_name']}/mysql/"
	local src_sshline="${HOSTINFO['dst_ssh']} -A -p${HOSTINFO['src_port']} -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${HOSTINFO['src_user']}@${HOSTINFO['src_host']}"
	local dst_sshline="${SSH_PATH} -A -p${HOSTINFO['dst_port']} -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${HOSTINFO['dst_user']}@${HOSTINFO['dst_host']}"
	local log_dir="$(get_opt 'log_directory')"
	local failstate=0
    
    if [[ -z "$dblist" ]]; then
    	log "[${HOSTINFO['src_name']}] Cannot found databases."
    	task_update $taskid finished end
    	return 0
    fi
    
    # Prepare / cleanup dumps directory
	${dst_sshline} "${src_sshline} \"mkdir -p '${dump_stor}'; rm \"${dump_stor}/{*.sql,*.sql.gz}\" > /dev/null 2>&1\""
	
	# Processing databases
    for dbase in $dblist; do
        local db_info=$($DB_QUERY "SELECT \`username\`, \`password\` FROM \`dbs\` WHERE \`hostid\` = '$hostid' AND \`name\` = '$dbase';")
        local db_user=$(echo "$db_info" | cut -d$'\t' -f1)
        local db_pass=$(echo "$db_info" | cut -d$'\t' -f2)
        
        # Dump
        log "[${HOSTINFO['src_name']}] Creating 'mysql' backup for database: '$dbase'"
        ${dst_sshline} "${src_sshline} \"mysqldump -c --user=$db_user --password=$db_pass -d $dbase > /${dump_stor}/${dbase}.sql\""
        local err_code="$?"
		if [[ ! "$err_code" -eq "0" ]]; then
			log "[${HOSTINFO['src_name']}] SQL dump error: $dbase, code $err_code"
			((failstate+=1))
			continue
		fi
		
		# Compress
		log "[${HOSTINFO['src_name']}] Compressing 'mysql' backup for database: '$dbase'"
        ${dst_sshline} "${src_sshline} \"gzip /${dump_stor}/${dbase}.sql\""
        local err_code="$?"
		if [[ ! "$err_code" -eq "0" ]]; then
			log "[${HOSTINFO['src_name']}] Compressing error: $dbase, code $err_code"
			((failstate+=1))
			continue
		fi
	done
	
	# Download dumps to destination host
	local rsync_opt="$(get_opt 'rsync_opt')"
	local rsync="${HOSTINFO['dst_rsync']} ${rsync_opt}"
	log "[${HOSTINFO['src_name']}] Downloading mysql dumps to '${HOSTINFO['dst_host']}'"
	${dst_sshline} "${rsync} --out-format '[$(date +'%Y-%m-%d %H:%M')][RSYNC] [${HOSTINFO['src_name']}] %n' -e '${HOSTINFO['dst_ssh']} -p${HOSTINFO['src_port']}' --delete --backup-dir=${backup_stor}/$(date +'%Y%m%d_%H%M')/ ${HOSTINFO['src_user']}@${HOSTINFO['src_host']}:/${dump_stor}/*.sql.gz ${backup_stor}/current/"
    local err_code="$?"
    if [[ ! "$err_code" -eq "0" ]]; then
        log "[${HOSTINFO['src_name']}] Error occured while downloading dumps, code $err_code"
        ((failstate+=1))
    fi
    
    # Incremental backup retention
    local incr_limit="$(get_opt 'incr_limit')"
    if [[ "${incr_limit}" =~ ^[0-9]+$ ]] ; then
        log "[${HOSTINFO['src_name']}] Incremental backups cleaning up."
        ${dst_sshline} "cd \"${backup_stor}\"; find . -maxdepth 1 -type d -name '*[0-9][0-9][0-9][0-9][0-1][0-9][0-3][0-9]_[0-2][0-9][0-6][0-9]*' | sort | head -n-${incr_limit} | xargs rm -rf"
    else
        log "[${HOSTINFO['src_name']}] Option '${incr_limit}' have invalid non-numeric value. Incremental copies will not be rotated."
        ((failstate+=1))
    fi
    
    if [[ "$failstate" -eq "0" ]]; then
        log "[${HOSTINFO['src_name']}] MySQL databases backed up successfully."
        task_update $taskid finished end
    else
        log "[${HOSTINFO['src_name']}] MySQL databases backup failed ($failstate errors)."
        task_update $taskid failed end
    fi
}

function backup_system() {
    local hostid=$1
	local taskid=$2
	task_update $taskid running start
	backup_hostinfo $hostid
	
    local rsync_opt="$(get_opt 'rsync_opt')"
	local rsync_excld="$(get_opt 'rsync_excludes')"
	[[ -n "${HOSTINFO['src_excld']}" ]] && rsync_excld+=",${HOSTINFO['src_excld']}"
	local backup_stor="${HOSTINFO['dst_path']}/${HOSTINFO['src_name']}/system/"
	local dst_sshline="${SSH_PATH} -A -p${HOSTINFO['dst_port']} -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${HOSTINFO['dst_user']}@${HOSTINFO['dst_host']}"
    local rsync="${HOSTINFO['dst_rsync']} ${rsync_opt} --exclude={$rsync_excld}"
    local log_dir="$(get_opt 'log_directory')"
    local failstate=0
    
    # Rsync system
    log "[${HOSTINFO['src_name']}] Backuping ${HOSTINFO['src_name']} - ${HOSTINFO['src_host']} --> ${HOSTINFO['dst_host']} (Task: #$2)"
    ${dst_sshline} "${rsync} --out-format '[$(date +'%Y-%m-%d %H:%M')][RSYNC] [${HOSTINFO['src_name']}] %n' -e '${HOSTINFO['dst_ssh']} -p${HOSTINFO['src_port']}' --delete --backup-dir=${backup_stor}/$(date +'%Y%m%d_%H%M')/ ${HOSTINFO['src_user']}@${HOSTINFO['src_host']}:/ ${backup_stor}/current/"
    local err_code="$?"
    if [[ ! "$err_code" -eq "0" ]]; then
        log "[${HOSTINFO['src_name']}] Error occured while downloading system, code $err_code"
        ((failstate+=1))
    fi
    
    # Incremental backup retention
    local incr_limit="$(get_opt 'incr_limit')"
    if [[ "${incr_limit}" =~ ^[0-9]+$ ]] ; then
        log "[${HOSTINFO['src_name']}] Incremental backups cleaning up."
        ${dst_sshline} "cd \"${backup_stor}\"; find . -maxdepth 1 -type d -name '*[0-9][0-9][0-9][0-9][0-1][0-9][0-3][0-9]_[0-2][0-9][0-6][0-9]*' | sort | head -n-${incr_limit} | xargs rm -rf"
    else
        log "[${HOSTINFO['src_name']}] Option '${incr_limit}' have invalid non-numeric value. Incremental copies will not be rotated."
        ((failstate+=1))
    fi
    
    if [[ "$failstate" -eq "0" ]]; then
        log "[${HOSTINFO['src_name']}] System backed up successfully"
    	task_update $taskid finished end
    else
        log "[${HOSTINFO['src_name']}] Error occured while backuping system ($failstate errors)"
        task_update $taskid failed end
    fi
}

function check_running() {
    sleep 1
    while [[ -n $($DB_QUERY "SELECT \`id\` from \`tasks\` WHERE \`status\` = 'running';") ]]; do
        sleep 1
    done
}

[[ -z "$1" ]] && help && exit 1

declare -A HOSTLIST
declare -A HOSTINFO
check_backupdb
ssh_check
get_hosts "$1"
args_logic "$@"
check_running
