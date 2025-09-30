#!/usr/bin/env bash

# Developed by Anton Samsonov <devel@zxlab.ru>
# Licensed under the terms of Unlicense: https://unlicense.org/

function ShowBanner ()
{
	echo "${APP_BANNER}"
}

function ShowSyntax ()
{
	echo 'Syntax:'
	echo "	${APP_NAME} [-hlnrRvV] [-p|t|T STR] [-i IN] [-o OUT] [PACKAGE...]"
}

function ShowTip ()
{
	echo ''
	ShowSyntax
	echo ''
	echo "Invoke with '-h' to get help."
}

function ShowHelp ()
{
	ShowBanner
	echo 'Prints package dependency tree or flattened recursive list.'
	echo ''
	ShowSyntax
	echo ''
	echo 'Void options:'
	echo '	-h	Show this help page.'
	echo '	-l	Print flattened list (rather than a tree).'
	echo '	-n	Print number of direct dependencies.'
	echo '	-r	Use reverse dependencies.'
	echo '	-R	Do not repeat sub-trees already printed before.'
	echo '	-v	Increase verbosity level.'
	echo '	-V	Print program name and version.'
	echo ''
	echo 'Scalar options:'
	echo '	-i LISTFILE	Read package list from file.'
	echo '	-o TREEFILE	Output tree (or flattened list) to file.'
	echo '	-p PREFIX	Indentation prefix for list and tree items.'
	echo '	-t INDENT	Indentation string for each tree level.'
	echo '	-T SUFFIX	Indentation suffix for tree items.'
}

function UnsetHint ()
{
	if [[ -z "${HINT}" ]] || ${TERMPIPE} || (( VERBOSITY >= 2 )) ; then
		return
	fi
	HINT="$(echo -n "${HINT}" | tr -c '\b' '\b')"
	echo -n "${HINT}"
	echo -n "${HINT}" | tr -c ' ' ' '
	echo -n "${HINT}"
	HINT=''
}

function SetHint ()
{
	if (( VERBOSITY < 1 )) ; then
		return
	fi
	declare TEXT="$1"
	UnsetHint
	HINT="${TEXT}"
	if ${TERMPIPE} || (( VERBOSITY >= 2 )) ; then
		echo "${HINT}"
	else
		echo -n "${HINT}"
	fi
}

function SetHintFromParents ()
{
	declare -i ITEMS=${#PARENTS[@]}
	declare -i INDEX=1
	declare REST=" +${ITEMS}..."
	declare -i RESERVED=$(( ${#REST} + 1 ))
	declare -i REMAINING=$(( TERMWIDTH - RESERVED ))
	declare TEXT="${PARENTS[0]}"
	(( REMAINING -= ${#TEXT} ))
	while (( INDEX < ITEMS )) && (( REMAINING >= 0 )) ; do
		REST=" ${PARENTS[$INDEX]}"
		if (( ${#REST} > REMAINING )) ; then
			break
		fi
		TEXT+="${REST}"
		(( REMAINING -= ${#REST} ))
		(( ++INDEX ))
	done
	if (( INDEX < ITEMS )) ; then
		(( ITEMS -= INDEX ))
		TEXT+=" +${ITEMS}..."
	fi
	SetHint "${TEXT}"
}

function SetHintFromAction ()
{
	declare TEXT="$1"
	if (( VERBOSITY >= 2 )) || [[ -n "${OUTFILE}" ]] ; then
		SetHint "${TEXT}"
	fi
}

function SetRoots ()
{
	if [[ -n "${FROMFILE}" ]] ; then
		if (( $# > 0 )) ; then
			echo "Positional arguments unused in '-f' mode ($#): $*" 1>&2
			exit 1
		fi
		if [[ "${FROMFILE}" == '-' ]] ; then
			readarray -t ROOTS
		else
			readarray -t ROOTS 0<"${FROMFILE}"
		fi
	else
		ROOTS=("$@")
	fi
	if (( ${#ROOTS[@]} == 0 )) ; then
		echo 'No packages specified.' 1>&2
		ShowTip
		exit 1
	fi
	readarray -t ROOTS 0< <(printf '%s\n' "${ROOTS[@]}" | sort --unique)
	if (( ${#ROOTS[@]} == 1 )) && [[ -z "${ROOTS[0]}" ]] ; then
		exit 0
	fi
}

function SetParents ()
{
	if (( "${#SUBJECTS[@]}" == 0 )) ; then
		return 1
	fi
	readarray -t SUBJECTS 0< <(printf '%s\n' "${SUBJECTS[@]}" | sort --unique)
	PARENTS=()
	declare PARENT
	for PARENT in "${SUBJECTS[@]}" ; do
		if [[ ! -v TREE["${PARENT}"] ]] ; then
			PARENTS+=("${PARENT}")
		fi
	done
	SUBJECTS=()
	CHILDREN=()
	(( ${#PARENTS[@]} != 0 ))
}

function SetDeps ()
{
	if [[ -z "${PARENT}" ]] ; then
		true
	elif (( ${#CHILDREN[@]} == 0 )) ; then
		TREE["${PARENT}"]=''
	else
		readarray -t CHILDREN 0< <(printf '%s\n' "${CHILDREN[@]}" | sort --version-sort --unique)
		if ${STOREDEPS} ; then
			TREE["${PARENT}"]="${CHILDREN[*]}"
		else
			TREE["${PARENT}"]=''
		fi
		SUBJECTS+=("${CHILDREN[@]}")
		CHILDREN=()
	fi
}

function GetFDeps ()
{
	declare PARENT=''
	declare CHILD
	declare RELATION
	CHILDREN=()
	while read -r RELATION CHILD ; do
		if [[ -z "${CHILD}" ]] && [[ "${RELATION}" != *':' ]] ; then
			if [[ -z "${RELATION}" ]] ; then
				continue
			fi
			SetDeps
			PARENT="${RELATION}"
			continue
		fi
		case "${RELATION}" in
		'Depends:'|'Pre-Depends:'|'PreDepends:') CHILDREN+=("${CHILD}") ;;
		*':') RELATION='-' ;;
		*)
			echo "Unknown relationship type: ${PARENT} ${RELATION} ${CHILD}." 1>&2
			continue
		esac
	done 0< <("${CMD[@]}" 2>/dev/null)
	SetDeps
}

function GetRDeps ()
{
	declare PARENT=''
	declare CHILD
	declare RELATION=''
	declare LINE
	while IFS='' read -r LINE ; do
		if [[ -z "${LINE}" ]] ; then
			continue
		elif [[ -z "${PARENT}" ]] && [[ "${LINE}" != *' '* ]] ; then
			PARENT="${LINE}"
		elif [[ -z "${RELATION}" ]] && [[ -n "${PARENT}" ]] ; then
			RELATION="${LINE}"
			case "${RELATION}" in
			'Reverse Depends:') RELATION='+' ;;
			*':') RELATION='-' ;;
			*)
				echo "Unknown relationship type: ${PARENT} ${RELATION}." 1>&2
				continue
			esac
		elif [[ "${LINE}" == ' '* ]] && [[ "${RELATION}" == '+' ]] ; then
			read -r CHILD 0<<<"${LINE}"
			CHILDREN+=("${CHILD}")
		elif [[ "${LINE}" != *' '* ]] && [[ -n "${PARENT}" ]] && [[ "${RELATION}" == '+' ]] ; then
			SetDeps
			PARENT="${LINE}"
			RELATION=''
		else
			echo "Unrecognized line format for package ${PARENT}: '${LINE}'." 1>&2
			continue
		fi
	done 0< <("${CMD[@]}" 2>/dev/null)
	SetDeps
}

function GetDeps ()
{
	declare -a SUBJECTS=("$@")	# All to-be-investigated packages (may be redundant).
	declare -a PARENTS		# Deduplicated package names to investigate.
	declare -a CHILDREN		# Child packages of a package being investigated.
	declare -a CMD
	while SetParents ; do
		if ${REVERSE} ; then
			CMD=(apt-cache rdepends "${PARENTS[@]}")
		else
			CMD=(apt-cache depends "${PARENTS[@]}")
		fi
		case ${VERBOSITY} in
		0)	true ;;
		1|2)	SetHintFromParents ;;
		*)	echo "${CMD[*]}"
		esac
		if ${REVERSE} ; then
			GetRDeps
		else
			GetFDeps
		fi
		case ${VERBOSITY} in
		1)	UnsetHint ;;
		esac
	done
}

function PrintTrees ()
{
	declare INDENT="$1"
	shift
	declare -a PARENTS=("$@")
	declare -a CHILDREN
	declare PREFIX
	declare PARENT
	for PARENT in "${PARENTS[@]}" ; do
		PREFIX="${TREE_PREFIX}${INDENT}${TREE_SUFFIX}"
		if [[ -v BRANCH["${PARENT}"] ]] ; then
			echo "${PREFIX}${PARENT} (loop!)" 1>&3
			continue
		elif [[ ! -v TREE["${PARENT}"] ]] ; then
			echo "${PREFIX}${PARENT} (missing!)" 1>&3
			continue
		fi
		read -r -a CHILDREN 0<<<"${TREE[$PARENT]}"
		if ! ${REPEAT} && (( ${#CHILDREN[@]} == 1 )) && [[ "${CHILDREN[0]}" == '*' ]] ; then
			echo "${PREFIX}${PARENT} (repeating)" 1>&3
			continue
		elif ${NUMBERS} ; then
			echo "${PREFIX}${PARENT} (${#CHILDREN[@]})" 1>&3
		else
			echo "${PREFIX}${PARENT}" 1>&3
		fi
		if ! ${REPEAT} && (( ${#CHILDREN[@]} >= 1 )) ; then
			TREE["${PARENT}"]='*'
		fi
		BRANCH["${PARENT}"]='+'
		PrintTrees "${INDENT}${TREE_INDENT}" "${CHILDREN[@]}"
		unset BRANCH["${PARENT}"]
	done
}

function PrintLinear ()
{
	declare PREFIX="${TREE_PREFIX}"
	declare -a PARENTS
	readarray -t PARENTS 0< <(printf '%s\n' "${!TREE[@]}" "${ROOTS[@]}" | sort --version-sort --unique)
	if ${NUMBERS} || (( ${#PARENTS[@]} != ${#TREE[@]} )) ; then
		declare PARENT
		declare -a CHILDREN
		for PARENT in "${PARENTS[@]}" ; do
			if [[ ! -v TREE["${PARENT}"] ]] ; then
				echo "${PREFIX}${PARENT} (missing!)" 1>&3
				continue
			fi
			if ${NUMBERS} ; then
				read -r -a CHILDREN 0<<<"${TREE[$PARENT]}"
				echo "${PREFIX}${PARENT} (${#CHILDREN[@]})" 1>&3
			else
				echo "${PREFIX}${PARENT}" 1>&3
			fi
		done
	else
		printf "${PREFIX}%s\n" "${PARENTS[@]}" 1>&3
	fi
}



set -o nounset

declare APP_NAME="${0##*/}"	# apt-tree.sh
declare APP_VERSION='1.0.0'
declare APP_BANNER="${APP_NAME} ${APP_VERSION}"

declare -x LC_MESSAGES='C'
declare -A TREE=()
declare -A BRANCH=()
declare -a ROOTS=()

declare TREE_PREFIX=''
declare TREE_INDENT=$'\t'
declare TREE_SUFFIX=''
declare FROMFILE=''
declare OUTFILE=''
declare LINEAR=false
declare NUMBERS=false
declare REPEAT=true
declare REVERSE=false
declare STOREDEPS=true

declare HINT=''
declare TERMPIPE=false
declare -i TERMWIDTH=0
declare -i VERBOSITY=0


declare OPTKEY
declare OPTARG
declare -i OPTIND

while getopts ':hi:lno:p:rRt:T:vV' OPTKEY ; do
	case "${OPTKEY}" in
	'h') ShowHelp ; exit 0 ;;
	'i') FROMFILE="${OPTARG}" ;;
	'l') LINEAR=true ;;
	'n') NUMBERS=true ;;
	'o') OUTFILE="${OPTARG}" ;;
	'p') TREE_PREFIX="${OPTARG}" ;;
	'r') REVERSE=true ;;
	'R') REPEAT=false ;;
	't') TREE_INDENT="${OPTARG}" ;;
	'T') TREE_SUFFIX="${OPTARG}" ;;
	'v') (( ++VERBOSITY )) ;;
	'V') ShowBanner ; exit 0 ;;
	*)
		echo "Unknown option '${OPTARG}'." 1>&2
		ShowTip
		exit 1 ;;
	esac
done
shift $(( OPTIND - 1 ))

if [[ ! -t 1 ]] ; then
	TERMPIPE=true
	TERMWIDTH=80
elif (( VERBOSITY >= 1 )) && (( VERBOSITY <= 2 )) && command -v tput 1>/dev/null ; then
	TERMWIDTH="$(tput cols)"
else
	TERMWIDTH=80
fi

if [[ -n "${OUTFILE}" ]] && [[ "${OUTFILE}" != '-' ]] ; then
	exec 3>"${OUTFILE}"
else
	exec 3>&1
fi

if (( VERBOSITY >= 1 )) ; then
	SetHint "${APP_BANNER}"
fi

if ${LINEAR} && ! ${NUMBERS} ; then
	STOREDEPS=false
fi

SetRoots "$@"
GetDeps "${ROOTS[@]}"

if ${LINEAR} ; then
	SetHintFromAction 'Printing flat list...'
	PrintLinear
	SetHintFromAction 'Finished printing flat list.'
	UnsetHint
else
	SetHintFromAction 'Printing tree...'
	PrintTrees '' "${ROOTS[@]}"
	SetHintFromAction 'Finished printing tree.'
	UnsetHint
fi

exec 3>&-
