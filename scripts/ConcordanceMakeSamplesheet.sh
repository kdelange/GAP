#!/bin/bash

set -e
set -u

# executed by the umcg-gd-ateambot, part of the NGS_Automated.


if [[ "${BASH_VERSINFO}" -lt 4 || "${BASH_VERSINFO[0]}" -lt 4 ]]
then
    echo "Sorry, you need at least bash 4.x to use ${0}." >&2
    exit 1
fi


# Env vars.
export TMPDIR="${TMPDIR:-/tmp}" # Default to /tmp if $TMPDIR was not defined.
SCRIPT_NAME="$(basename ${0})"
SCRIPT_NAME="${SCRIPT_NAME%.*sh}"
INSTALLATION_DIR="$(cd -P "$(dirname "${0}")/.." && pwd)"
LIB_DIR="${INSTALLATION_DIR}/automated/lib"
CFG_DIR="${INSTALLATION_DIR}/automated/etc"
HOSTNAME_SHORT="$(hostname -s)"
ROLE_USER="$(whoami)"
REAL_USER="$(logname 2>/dev/null || echo 'no login name')"



#
##
### Functions.
##
#

if [[ -f "${LIB_DIR}/sharedFunctions.bash" && -r "${LIB_DIR}/sharedFunctions.bash" ]]
then
    source "${LIB_DIR}/sharedFunctions.bash"
else
    printf '%s\n' "FATAL: cannot find or cannot access sharedFunctions.bash"
    exit 1
fi

function showHelp() {
        #
        # Display commandline help on STDOUT.
        #
        cat <<EOH
======================================================================================================================
Scripts to make automatically a samplesheet for the concordance check between ngs and array data.
ngs.vcf should be in /groups/${NGSGROUP}/${TMP_LFS}/Concordance/ngs/.
array.vcf should be in /groups/${ARRAYGROUP}/${TMP_LFS}/Concordance/array/.


Usage:

        $(basename $0) OPTIONS

Options:

        -h   Show this help.
        -g   ngsgroup (the group which runs the script and countains the ngs.vcf files, umcg-gd).
        -a   arraygroup (the group where the array.vcf files are, umcg-gap )
        -l   Log level.
                Must be one of TRACE, DEBUG, INFO (default), WARN, ERROR or FATAL.
                
Config and dependencies:

    This script needs 3 config files, which must be located in ${CFG_DIR}:
     1. <group>.cfg     for the group specified with -g
     2. <host>.cfg        for this server. E.g.:"${HOSTNAME_SHORT}.cfg"
     3. sharedConfig.cfg  for all groups and all servers.
    In addition the library sharedFunctions.bash is required and this one must be located in ${LIB_DIR}.

======================================================================================================================

EOH
        trap - EXIT
        exit 0
}


#
##
### Main.
##
#

#
# Get commandline arguments.
#
log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "Parsing commandline arguments..."
declare group=''
while getopts "g:a:l:h" opt
do
        case $opt in
                h)
                        showHelp
                        ;;
                g)
                        NGSGROUP="${OPTARG}"
                        ;;
                a)
                        ARRAYGROUP="${OPTARG}"
                        ;;
                l)
                        l4b_log_level=${OPTARG^^}
                        l4b_log_level_prio=${l4b_log_levels[${l4b_log_level}]}
                        ;;
                \?)
                        log4Bash "${LINENO}" "${FUNCNAME:-main}" '1' "Invalid option -${OPTARG}. Try $(basename $0) -h for help."
                        ;;
                :)
                        log4Bash "${LINENO}" "${FUNCNAME:-main}" '1' "Option -${OPTARG} requires an argument. Try $(basename $0) -h for help."
                        ;;
        esac
done

#
# Check commandline options.
#
if [[ -z "${NGSGROUP:-}" ]]
then
        log4Bash 'FATAL' "${LINENO}" "${FUNCNAME:-main}" '1' 'Must specify a ngs-group with -g. For the ngs.vcf files'
fi

if [[ -z "${ARRAYGROUP:-}" ]]
then
        log4Bash 'FATAL' "${LINENO}" "${FUNCNAME:-main}" '1' 'Must specify an array-group with -a. for the array.vcf files'
fi
#
# Source config files.
#
log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "Sourcing config files..."
declare -a configFiles=(
        "${CFG_DIR}/${NGSGROUP}.cfg"
        "${CFG_DIR}/${HOSTNAME_SHORT}.cfg"
        "${CFG_DIR}/sharedConfig.cfg"
        "${HOME}/molgenis.cfg"
)

for configFile in "${configFiles[@]}"; do 
        if [[ -f "${configFile}" && -r "${configFile}" ]]
        then
                log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "Sourcing config file ${configFile}..."
                #
                # In some Bash versions the source command does not work properly with process substitution.
                # Therefore we source a first time with process substitution for proper error handling
                # and a second time without just to make sure we can use the content from the sourced files.
                #
                mixed_stdouterr=$(source ${configFile} 2>&1) || log4Bash 'FATAL' ${LINENO} "${FUNCNAME:-main}" ${?} "Cannot source ${configFile}."
                source ${configFile}  # May seem redundant, but is a mandatory workaround for some Bash versions.
        else
                log4Bash 'FATAL' "${LINENO}" "${FUNCNAME:-main}" '1' "Config file ${configFile} missing or not accessible."
        fi
done

#
# Make sure to use an account for cron jobs and *without* write access to prm storage.
#

if [[ "${ROLE_USER}" != "${ATEAMBOTUSER}" ]]
then
        log4Bash 'FATAL' "${LINENO}" "${FUNCNAME:-main}" '1' "This script must be executed by user ${ATEAMBOTUSER}, but you are ${ROLE_USER} (${REAL_USER})."
fi


module load HTSlib/1.3.2-foss-2015b
module load BEDTools/2.25.0-foss-2015b
module list


concordanceDir="/groups/${NGSGROUP}/${TMP_LFS}/Concordance/"
ngsVcfDir="${concordanceDir}/ngs/"
arrayVcfDir="/groups/${ARRAYGROUP}/${TMP_LFS}/Concordance/array/"

for vcfFile in $(find "${ngsVcfDir}" -type f -iname "*final.vcf")
do
    echo "_____________________________________________________________" ##Can be removed later, more easy to see when a new sample is processed
    log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "processing ngs-vcf ${vcfFile}"
    ngsVcfId=$(basename "${vcfFile}" .final.vcf)
    ngsBarcode=$(grep "##FastQ_Barcode=" "${vcfFile}" | awk 'BEGIN {FS="="}{OFS="_"} {print _,$2}')
    ngsInfo=$(echo "${ngsVcfId}" | awk 'BEGIN {FS="_"}{OFS="_"}{print $3,$4,$5}')
    ngsInfoList=$(echo "${ngsInfo}${ngsBarcode}")
    dnaNo=$(echo "${ngsVcfId}" | awk 'BEGIN {FS="_"}{print substr($3,4)}')

    log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "info from ngs.vcf: ${ngsInfoList}"

    checkArrayVcf=$(find "${arrayVcfDir}" -type f -iname "DNA-${dnaNo}_"*".FINAL.vcf")

    if [[ -z "${checkArrayVcf}" ]]
    then
        log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "there is not (yet) an array vcf file precent for ${ngsVcfId}"
        continue
    else
        arrayFile=$(ls -1 "${arrayVcfDir}/DNA-${dnaNo}_"*".FINAL.vcf")
        arrayId="$(basename "${arrayFile}" .FINAL.vcf)"
        arrayInfoList=$(echo "${arrayId}" | awk 'BEGIN {FS="_"}{OFS="_"}{print $1,$2,$3,$5,$6}')
        log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "processing array vcf ${arrayFile}"
        log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "info from array.vcf: ${arrayInfoList}"
    fi

    if [[ -f "${arrayInfoList}_${ngsInfoList}.sampleId.txt" ]]
    then
        log4Bash 'DEBUG' "${LINENO}" "${FUNCNAME:-main}" '0' "the concordance between ${arrayInfoList} ${ngsInfoList} is being calculated"
        continue
    else
        echo -e "data1Id\tdata2Id\n${arrayId}\t${ngsVcfId}" > "${concordanceDir}/samplesheets/${arrayInfoList}_${ngsInfoList}.sampleId.txt"
    fi 

done

trap - EXIT
exit 0



