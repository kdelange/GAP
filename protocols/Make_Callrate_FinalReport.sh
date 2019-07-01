#!/bin/bash

#MOLGENIS walltime=05:59:00 mem=10gb ppn=6

#string Project
#list Sample_ID
#list SentrixBarcode_A
#list SentrixPosition_A
#string resultDir
#string CallrateDir
#string gapVersion
#string logsDir
#string intermediateDir

#Function to check if array contains value
array_contains () {
	local array="$1[@]"
	local seeking=$2
	local in=1
	for element in "${!array-}"; do
		if [[ "$element" == "$seeking" ]]; then
			in=0
			break
		fi
	done
	return $in
}

module load "${gapVersion}"
module list

set -e
set -u

INPUTARRAYS=()

for array in "${SentrixBarcode_A[@]}"
do
	array_contains INPUTARRAYS "${array}" || INPUTARRAYS+=("$array")    # Make a list of unique SentrixBarcode_A per project.
done

## Merge all Callrate files from different SentrixBarcode_A to one project Callrate file.
echo -e "Sample ID\tCall Rate\tGender" > "${CallrateDir}/Callrates_${Project}.txt"

for i in "${INPUTARRAYS[@]}"
do
	echo "${CallrateDir}/Callrates_${i}.txt"
	awk 'FNR>1' "${CallrateDir}/Callrates_${i}.txt" >> "${CallrateDir}/Callrates_${Project}.txt"
done


#Put results in resultsfolder
rsync -a "${CallrateDir}/Callrates_${Project}.txt" "${resultDir}"
