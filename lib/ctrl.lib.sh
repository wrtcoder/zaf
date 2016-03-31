# Control file related functions

# Get block from stdin
# $1 option
# $2 name
zaf_ctrl_get_items() {
	grep '^Item ' | cut -d ' ' -f 2 | cut -d ':' -f 1 | tr '\r\n' ' '
}

# Get item body from stdin
# $1 itemname
zaf_ctrl_get_item_block() {
	grep -v '^#' | awk '/^Item '$1'/ { i=0;
	while (i==0) {
		getline;
		if (/^\/Item/) exit;
		print $0;
	}};
	END {
		exit i==0;
	}'
}

# Get global plugin block body from stdin
# $1 itemname
zaf_ctrl_get_global_block() {
	grep -v '^#' | awk '{ i=0;
	while (i==0) {
		getline;
		if (/^Item /) exit;
		print $0;
	}}'
}

# Get item multiline option
# $1 optionname
zaf_block_get_moption() {
	awk '/^'$1'::$/ { i=0;
	while (i==0) {
		getline;
		if (/^::$/) {i=1; continue;};
		print $0;
	}};
	END {
		exit i==0;
	}
	'
}

# Get item singleline option from config block on stdin
# $1 optionname
zaf_block_get_option() {
	grep "^$1:" | cut -d ' ' -f 2- | tr -d '\r\n'
}

# Get global option (single or multiline)
# $1 - control file
# $2 - option name
zaf_ctrl_get_global_option() {
	zaf_ctrl_get_global_block <$1 | zaf_block_get_moption "$2" || zaf_ctrl_get_global_block <$1 | zaf_block_get_option "$2"
}
# Get item specific option (single or multiline)
# $1 - control file
# $2 - item name
# $3 - option name
zaf_ctrl_get_item_option() {
	zaf_ctrl_get_item_block <$1 "$2" | zaf_block_get_moption "$3" || zaf_ctrl_get_item_block <$1 "$2" | zaf_block_get_option "$3"
}

zaf_ctrl_check_deps() {
	local deps
	deps=$(zaf_ctrl_get_global_block <$1 | zaf_block_get_option "Depends-${ZAF_PKG}" )
	zaf_os_specific zaf_check_deps $deps
	deps=$(zaf_ctrl_get_global_block <$1 | zaf_block_get_option "Depends-bin" )
	for cmd in $deps; do
		if ! which $cmd >/dev/null; then
			zaf_wrn "Missing binary dependency $cmd. Please install it first."
                        return 1
		fi
	done
}

# Install binaries from control
# $1 control
# $2 plugindir
zaf_ctrl_install() {
	local binaries
	local pdir
	local script
	local cmd

	pdir="$2"
	binaries=$(zaf_ctrl_get_global_block <$1 | zaf_block_get_option "Install-bin" | zaf_far '{PLUGINDIR}' "$plugindir" )
	for b in $binaries; do
		zaf_fetch_url "$url/$b" >"${ZAF_TMP_DIR}/$b"
                zaf_install_bin "${ZAF_TMP_DIR}/$b" "$pdir"
	done
	script=$(zaf_ctrl_get_global_block <$1 | zaf_block_get_moption "Install-script" | zaf_far '{PLUGINDIR}' "$plugindir" )
	[ -n "$script" ] && eval "$script"
	cmd=$(zaf_ctrl_get_global_block <$1 | zaf_block_get_option "Install-cmd" | zaf_far '{PLUGINDIR}' "$plugindir" )
	[ -n "$cmd" ] && $cmd
}

# Generates zabbix cfg from control file
# $1 control
# $2 pluginname
zaf_ctrl_generate_cfg() {
	local items
	local cmd
	local ilock

	items=$(zaf_ctrl_get_items <"$1")
	for i in $items; do
            ilock=$(echo $i | tr -d '[]*&;:')
            cmd=$(zaf_ctrl_get_item_option $1 $i "Cmd")
            if [ -n "$cmd" ]; then
                echo "UserParameter=$2.${i},$cmd";
                continue
            fi
            cmd=$(zaf_ctrl_get_item_option $1 $i "Function")
            if [ -n "$cmd" ]; then
                echo "UserParameter=$2.${i},${ZAF_LIB_DIR}/preload.sh $cmd";
                continue;
            fi
            cmd=$(zaf_ctrl_get_item_option $1 $i "Script")
            if [ -n "$cmd" ]; then
                zaf_ctrl_get_item_option $1 $i "Script" >${ZAF_TMP_DIR}/${ilock}.sh;
                zaf_install_bin ${ZAF_TMP_DIR}/${ilock}.sh ${ZAF_PLUGINS_DIR}/$2/
                echo "UserParameter=$2.${i},${ZAF_PLUGINS_DIR}/$2/${ilock}.sh";
                continue;
            fi
	done
}

