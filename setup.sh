#!/bin/bash

echo "Initialising..."

# Get the Account Id first so that it is populated in the values sourced from setup_args.txt
#awsAccountId=$(aws sts get-caller-identity --query "Account" --output text)

spinner="/-\|"

get_resource () {
    local  __resultvar=${1}

    printf "Fetching resource %s from %s outputs\n" ${3} ${2}
    local  response=$(aws cloudformation describe-stacks \
        --stack-name "${2}" \
        --query "Stacks[*].Outputs[?OutputKey=='${3}'].OutputValue" \
        --output text)

    eval ${__resultvar}="'${response}'"
}

fetch_pipeline_status() {
  aws codepipeline list-pipeline-executions \
        --pipeline-name ${pipelineName} \
        --max-items 1 \
        --query "pipelineExecutionSummaries[0].status" \
        --output text | head -n 1
}

#<REF/> https://stackoverflow.com/a/12694189
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${DIR}" ]]; then DIR="${PWD}"; fi
printf "DIR is %s\n" ${DIR}

# Load the necessary arguments from file
. ${DIR}/setup_args.txt

printf "Commencing setup...\n"

read -t ${inputTimeout} -p "Enter component name [${projectName}] or press <Enter> to accept default, you have ${inputTimeout}s: " inputProjectName

projectName=${inputProjectName:-$projectName}

printf "\n"

read -t ${inputTimeout} -p "Enter your Secret name of GitHub token stored in AWS Secrets Manager [${gitHubTokenSecret}], you have ${inputTimeout}s: " inputGitHubTokenSecret

gitHubTokenSecret=${inputGitHubTokenSecret:-$gitHubTokenSecret}

printf "\n"

read -t ${inputTimeout} -p "Enter your GitHub Packages (repo) URL to use as private Maven repo [${internalRepoURL}], you have ${inputTimeout}s: " inputGitHubMavenRepoURL

internalRepoURL=${inputGitHubMavenRepoURL:-$internalRepoURL}

printf "\n"

get_resource lambdaLayer "${parentName}-DEPLOY" "${layerName}"

OIFS=$IFS
IFS=":"
layerArnArray=(${lambdaLayer})
lambdaLayer="arn:aws:lambda:${layerArnArray[3]}:${layerArnArray[4]}:layer:${layerArnArray[6]}"
IFS=${OIFS}

printf "Fetching latest version of Lambda Layer: %s.\n" ${lambdaLayer}
lambdaLayerVersion=$(aws lambda list-layer-versions \
    --layer-name "${lambdaLayer}" \
    --query "LayerVersions[*].Version" \
    --max-items 1 \
    --output text | head -n 1)

printf "Latest version of Lambda Layer: %s. is %s\n" ${lambdaLayer} ${lambdaLayerVersion}


printf "Starting to setup %s\n" ${projectName}

printf "Deploying stack of %s\n" ${projectName}

aws cloudformation deploy \
    --template-file ${DIR}/project.yaml \
    --stack-name "${projectName}" \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
        ArtifactName="${projectName}" \
        LambdaLayerStackName="${parentName}-DEPLOY" \
        LambdaLayerVersion="${lambdaLayerVersion}" \
        GitHubOwner="${githubOwner}" \
        CodeRepository="${codeRepository}" \
        GitHubTokenSecret="${gitHubTokenSecret}" \
        InternalRepoURL="${internalRepoURL}" \
        TagRoot="${tagRoot}" \
        TagProject="${tagProject}" \
        TagComponent="JGLF" \
        #CreateGitHubWebHook=${createGitHubWebHook}

pipelineName=$(aws cloudformation describe-stacks \
    --stack-name "${projectName}" \
    --query "Stacks[*].Outputs[?OutputKey=='PipelineName'].OutputValue" \
    --output text)

printf "Deploying Lambda Function via Pipeline: %s\n" ${pipelineName}

pipelineStatus=$(fetch_pipeline_status)
waitTime=0
until [[ ${pipelineStatus} == "Succeeded" ]]; do
    minutes=$((${waitTime}/60))
    seconds=$((${waitTime}%60))
    printf "\rPipeline status is: ${pipelineStatus}. Waiting... ${spinner:i++%${#spinner}:1} [ %02dm %02ds ]" ${minutes} ${seconds}
    sleep 5
    waitTime=$((${waitTime}+5))
    pipelineStatus=$(fetch_pipeline_status)
done
printf "\nPipeline status is: %s\n" ${pipelineStatus}

printf "Completed setup of %s\n" ${projectName}
