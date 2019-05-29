#!/bin/bash

module list

host=$(hostname -s)
environmentParameters="parameters_${host}"

function showHelp() {
    #
    # Display commandline help on STDOUT.
    #
    cat <<EOH
===============================================================================================================
Script to generate a pipeline template to process Globol Screaning Array projects.
Usage:
    $(basename $0) OPTIONS
Options:
    -h   Show this help.
    -p   project
    -g   group (default=basename of ../../../ )
    -f   filePrefix (default=basename of this directory)
    -r   runID (default=run01)
    -t   tmpDirectory (default=basename of ../../ )
    -x   excludeGTCsFile ## waarom dit dit er in?
    -w   workdir (default=/groups/\${group}/\${tmpDirectory})

===============================================================================================================
EOH
    trap - EXIT
    exit 0
}

while getopts "t:g:w:f:p:r:x:h" opt;
do
    case $opt in h)showHelp;; t)tmpDirectory="${OPTARG}";; g)group="${OPTARG}";; w)workDir="${OPTARG}";; f)filePrefix="${OPTARG}";; p)project="${OPTARG}";; r)runID="${OPTARG}";; x)excludeGTCsFile="${OPTARG}";;
    esac
done

if [[ -z "${tmpDirectory:-}" ]]; then tmpDirectory=$(basename $(cd ../../ && pwd )) ; fi ; echo "tmpDirectory=${tmpDirectory}"
if [[ -z "${group:-}" ]]; then group=$(basename $(cd ../../../ && pwd )) ; fi ; echo "group=${group}"
if [[ -z "${workDir:-}" ]]; then workDir="/groups/${group}/${tmpDirectory}" ; fi ; echo "workDir=${workDir}"
if [[ -z "${filePrefix:-}" ]]; then filePrefix=$(basename $(pwd )) ; fi ; echo "filePrefix=${filePrefix}"
if [[ -z "${runID:-}" ]]; then runID="run01" ; fi ; echo "runID=${runID}"
if [[ -z  "${excludeGTCsFile}" ]];then excludeGTCsFile="FALSE" ; fi ; echo "excludeGTCsFile=${excludeGTCsFile}"
genScripts="${workDir}/generatedscripts/${filePrefix}/"
samplesheet="${genScripts}/${filePrefix}.csv" ; mac2unix "${samplesheet}"

### Which pipeline to run
sampleSheetColumnNames=()
sampleSheetColumnOffsets=()
IFS="${SAMPLESHEET_SEP}" sampleSheetColumnNames=($(head -1 "${samplesheet}"))
for (( _offset = 0 ; _offset < ${#sampleSheetColumnNames[@]:-0} ; _offset++ ))
do
    _sampleSheetColumnOffsets["${sampleSheetColumnNames[${_offset}]}"]="${_offset}"
done
if [[ ! -z "${sampleSheetColumnOffsets['pipeline']+isset}" ]]; then
    pipelineFieldIndex=$((${sampleSheetColumnOffsets['pipeline']} + 1))
    IFS=$'\n' pipeline=($(tail -n +2 "${sampleSheet}" | cut -d "${SAMPLESHEET_SEP}" -f ${pipelineFieldIndex} | head -1))
else
    pipeline="diagnostics"
fi

host=$(hostname -s)
echo "${host}"

projectDir="${workDir}/projects/${filePrefix}/${runID}/jobs/"

mkdir -p -m 2770 "${workDir}/projects/"
mkdir -p -m 2770 "${workDir}/projects/${filePrefix}/"
mkdir -p -m 2770 "${workDir}/projects/${filePrefix}/${runID}/"
mkdir -p -m 2770 "${workDir}/projects/${filePrefix}/${runID}/jobs/"


perl "${EBROOTGAP}/scripts/convertParametersGitToMolgenis.pl" "${EBROOTGAP}/parameters_${host}.csv" > "${genScripts}/parameters_host_converted.csv"
perl "${EBROOTGAP}/scripts/convertParametersGitToMolgenis.pl" "${EBROOTGAP}/parameters_${group}.csv" > "${genScripts}/parameters_group_converted.csv"
perl "${EBROOTGAP}/scripts/convertParametersGitToMolgenis.pl" "${EBROOTGAP}/parameters_${pipeline}.csv" > "${genScripts}/parameters_converted.csv"

sh "${EBROOTMOLGENISMINCOMPUTE}/molgenis_compute.sh" \
-p "${genScripts}/parameters_converted.csv" \
-p "${genScripts}/parameters_group_converted.csv" \
-p "${genScripts}/parameters_host_converted.csv" \
-p "${samplesheet}" \
-w "${EBROOTGAP}/Prepare_${pipeline}_workflow.csv" \
-weave \
--generate \
-rundir "${genScripts}/scripts" \
--runid "${runID}" \
-o "outputdir=scripts/jobs;\
mainParameters=${genScripts}/parameters_converted.csv;\
samplesheet=${samplesheet};\
gapVersion=$(module list | grep -o -P 'GAP(.+)');\
Project=${filePrefix};\
pipeline=${pipeline};\
runID=${runID};\
excludeGTCsFile=${excludeGTCsFile:-};"

