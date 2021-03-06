#!/bin/bash

printf "Initialising...\n"

spinner="/-\|"

END_STATE_CODES=( \
    "DELETE_COMPLETE" \
    "DELETE_FAILED")

get_resource () {
    local  __resultvar=${1}

    printf "Fetching resource %s from %s outputs\n" ${3} ${2}
    local  response=$(aws cloudformation describe-stacks \
        --stack-name "${2}" \
        --query "Stacks[*].Outputs[?OutputKey=='${3}'].OutputValue" \
        --output text)

    eval ${__resultvar}="'${response}'"
}

delete_stack () {
    printf "Deleting stack %s\n" ${1}
    aws cloudformation delete-stack --stack-name ${1}
}

fetch_stack_status() {
    aws cloudformation list-stacks \
        --query "StackSummaries[?StackId=='${1}'].StackStatus" \
        --output text
}

#<REF/> https://stackoverflow.com/a/12694189
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${DIR}" ]]; then DIR="${PWD}"; fi
printf "DIR is %s\n" ${DIR}

# Load the necessary arguments from the same setup args file
. ${DIR}/setup_args.txt

printf "Commencing tear down...\n"

read -t ${inputTimeout} -p "Enter component name [${projectName}] or press <Enter> to accept default, you have ${inputTimeout}s: " input
projectName=${input:-$projectName}

stacks=("${projectName}-DEPLOY" "${projectName}")

printf "\nStarting to tear down %s\n" ${projectName}

get_resource s3Bucket ${projectName} "BuildArtifactsBucketName"

for stack in ${stacks[@]}; do
    stackId=$(aws cloudformation describe-stacks \
        --stack-name "${stack}" \
        --query "Stacks[*].StackId" \
        --output text)

    delete_stack ${stackId}

    stackStatus=$(fetch_stack_status ${stackId})
    waitTime=0
    #<Ref/> https://stackoverflow.com/a/15394738
    until [[ " ${END_STATE_CODES[@]} " =~ " ${stackStatus} " ]]; do
        minutes=$((${waitTime}/60))
        seconds=$((${waitTime}%60))
        printf "\rStack status is: ${stackStatus}. Waiting... ${spinner:i++%${#spinner}:1} [ %02dm %02ds ]" ${minutes} ${seconds}
        sleep 5
        waitTime=$((${waitTime}+5))
        stackStatus=$(fetch_stack_status ${stackId})
    done
    printf "\nStack status is: %s.\n" ${stackStatus}
done

printf "\nDeleting S3 bucket : %s.\n" ${s3Bucket}
aws s3 rb "s3://${s3Bucket}" --force

printf  "Completed tearing down %s\n" ${projectName}
