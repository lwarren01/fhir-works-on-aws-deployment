#!/bin/bash

#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#

#Usage: ./install.sh <OPTIONAL PARAMETERS>

#Bugs:
#   -What if someone doesn't have AWS CLI installed?
#   -What if nothing is entered in aws configure?

##Usage information
function usage(){
    echo ""
    echo "Usage: $0 [required arguments] [optional arguments]"
    echo ""
    echo "Optional Parameters:"
    echo ""
    echo "    --stage (-s): Set stage for deploying AWS services (Default: 'dev')"
    echo "    --region (-r): Set region for deploying AWS services (Default: 'us-west-2')"
    echo "    --issuerEndpoint (-i): This is the endpoint that mints the access_tokens and will also be the issuer in the access_token as well."
    echo "    --oAuth2ApiEndpoint (-o): this is probably similar to your issuer endpoint but is the prefix to all OAuth2 APIs"
    echo "    --patientPickerEndpoint (-p): SMART on FHIR supports launch contexts and that will typically include a patient picker application that will proxy the /token and /authorize requests."
    echo "    --apigatewayMetricsEnabled: Is API gateway metics enabled for this FHIR Works instance (Default: false)"
    echo "    --alarmSubscriptionEndpoint: The HTTPS endpoint to be configured as a subscriber on the CloudWatch Alarm SNS Topic."
    echo "    --lambdaLatencyThreshold: lambda latency threshold in ms (Default: 3000)"
    echo "    --apigatewayLatencyThreshold: apigateway latency threshold in ms (Default: 500)"
    echo "    --apigatewayServerErrorThreshold: API gateway 5xxerror threshold (Default: 3)"
    echo "    --apigatewayClientErrorThreshold: API gateway 4xxerror threshold (Default: 5)"
    echo "    --lambdaErrorThreshold: lambda error latency threshold (Default: 1)"
    echo "    --ddbToESLambdaErrorThreshold: DDBToES lambda error threshold (Default: 1)"
    echo "    --help (-h): Displays this message"
    echo ""
    echo ""
}

function YesOrNo() {
        while :
        do
                read -p "$1 (yes/no): " answer
                case "${answer}" in
                    [yY]|[yY][eE][sS]) exit 0 ;;
                        [nN]|[nN][oO]) exit 1 ;;
                esac
        done
}

function install_dependencies(){
    #Dependencies:
        #   nodejs  ->  npm   -> serverless
        #           ->  yarn
        #   python3 ->  boto3

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        #Identify Linux distribution
        PKG_MANAGER=$( command -v yum || command -v apt-get )
        basepkg=`basename $PKG_MANAGER`

        # Identify kernel release
        KERNEL_RELEASE=$(uname -r)
        #Update package manager
        sudo $PKG_MANAGER update
        sudo $PKG_MANAGER upgrade

        #Yarn depends on node version >= 12.0.0
        if [ "$basepkg" == "apt-get" ]; then
            curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
            sudo apt-get install nodejs -y
        elif [ "$basepkg" == "yum" ]; then
            if [[ $KERNEL_RELEASE =~ amzn2.x86_64 ]]; then
                curl -sL https://rpm.nodesource.com/setup_12.x | bash -
                yum install nodejs -y
            else
                yum install nodejs12 -y
            fi
        fi

        type -a npm || sudo $PKG_MANAGER install npm -y

        type -a python3 || sudo $PKG_MANAGER install python3 -y
        type -a pip3 || sudo $PKG_MANAGER install python3-pip -y
        sudo pip3 install boto3

        type -a yarn 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            sudo npm install --global yarn@1.22.5
        fi

        sudo $PKG_MANAGER upgrade -y

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        #sudo -u $SUDO_USER removes brew's error message that brew should not be run as 'sudo'
        type -a brew 2>&1 || { error_msg="ERROR: brew is required to install packages."; return 1; }
        sudo -u $SUDO_USER brew install node@12
        sudo -u $SUDO_USER brew install python3
        sudo npm install --global yarn@1.22.5
        sudo pip3 install boto3
    else
        error_msg="ERROR: this install script is only supported on Linux or macOS."
        return 1
    fi

    echo "" >&2

    type -a node 2>&1 || { error_msg="ERROR: package 'nodejs' failed to install."; return 1; }
    type -a npm 2>&1 || { error_msg="ERROR: package 'npm' failed to install."; return 1; }
    type -a python3 2>&1 || { error_msg="ERROR: package 'python3' failed to install."; return 1; }
    type -a pip3 2>&1 || { error_msg="ERROR: package 'python3-pip' failed to install."; return 1; }
    type -a yarn 2>&1 || { error_msg="ERROR: package 'yarn' failed to install."; return 1; }

    return 0
}

#Function to parse YAML files
##Usage: eval $(parse_log <FILE_PATH> <PREFIX>)
##Output: adds variables from YAML file to namespace of script
##          variable names are prefixed with <PREFIX>, if supplied
##          sublists are marked with _
##
##Example:
##          testLevel1:
##              testLevel2: 3
##
##Example Output:
##          testLeve1_testLevel2=3
##
function parse_log() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function get_valid_pass(){
    matched=0
    while true; do
        if [ $matched == 1 ]; then
            echo -e "\nERROR: Passwords did not match. Please try again.\n" >&2
            matched=0
        fi
        read -s -p "Enter password: " s1
        if ! [[ ${#s1} -ge 8 && \
                ${#s1} -le 20 && \
                "$s1" == *[A-Z]* && \
                "$s1" == *[a-z]* && \
                "$s1" == *[0-9]* && \
                "$s1" == *['!'@#\$%^\&*\(\)_+""-\]\[]* ]]; then
            echo -e "\nERROR: Invalid password. Password must satisfy the following requirements: " >&2
            echo "  * 8-20 characters long" >&2
            echo "  * at least 1 lowercase character" >&2
            echo "  * at least 1 uppercase character" >&2
            echo "  * at least 1 special character (Any of the following: '!@#$%^\&*()[]_+-\")" >&2
            echo "  * at least 1 number character" >&2
            echo "" >&2
        else
            echo "" >&2
            read -s -p "Please confirm your password: " s2
            if [ "$s2" != "$s1" ]; then
                matched=1
            else
                break
            fi
        fi
    done

    echo "$s1"
}

#Function to wait for cfn to change state
#Usage: wait_for_cfn_changeset "ImportChangeSet" "AVAILABLE"
function wait_for_cfn_changeset(){
    change_set_name="$1"
    state="$2"
    
    # wait for changeset to be in a ready state for executeion
    echo "watiting for changeset to be $state"
    declare +r NUM_RETRIES=20
    declare +r SLEEP_TIME=3
    execution_status=""
    for (( i=1; i <=NUM_RETRIES; i++))
    do
        echo "Polling change-set status for execution status ${execution_status}"

        execution_status=$(aws cloudformation describe-change-set \
            --change-set-name "$change_set_name" \
            --stack-name "fhir-service-${stage}" \
        | jq -r '.ExecutionStatus')

        if [ "${execution_status}" == "$state" ]; then
            echo "change-set in $state"
            break
        else
            echo " ${SLEEP_TIME} seconds. Attempt ${i}/${NUM_RETRIES}..."
            sleep ${SLEEP_TIME}s
        fi
    done
}

#Change directory to that of the script (in case someone calls it from another folder)
cd "${0%/*}"
# Save parent directory
export PACKAGE_ROOT=${PWD%/*}

if [ "$DOCKER" != "true" -a "$EUID" -ne 0 ]
then
    echo "Error: installation requires elevated permissions. Please run as root using the 'sudo' command." >&2
    exit 1
fi

#Default values
issuerEndpoint="undefined"
oAuth2ApiEndpoint="undefined"
patientPickerEndpoint="undefined"
stage="dev"
region="us-west-2"
lambdaLatencyThreshold=3000
apigatewayMetricsEnabled=false
apigatewayLatencyThreshold=500
apigatewayServerErrorThreshold=3
apigatewayClientErrorThreshold=5
lambdaErrorThreshold=1
ddbToESLambdaErrorThreshold=1
alarmSubscriptionEndpoint="undefined"

#Parse commandline args
while [ "$1" != "" ]; do
    case $1 in
        -i | --issuerEndpoint )                     shift
                                                    issuerEndpoint=$1
                                                    ;;
        -o | --oAuth2ApiEndpoint )                  shift
                                                    oAuth2ApiEndpoint=$1
                                                    ;;
        -p | --patientPickerEndpoint )              shift
                                                    patientPickerEndpoint=$1
                                                    ;;
        -s | --stage )                              shift
                                                    stage=$1
                                                    ;;
        -r | --region )                             shift
                                                    region=$1
                                                    ;;
        --alarmSubscriptionEndpoint )               shift
                                                    alarmSubscriptionEndpoint=$1
                                                    ;;
        --lambdaLatencyThreshold )                  shift
                                                    lambdaLatencyThreshold=$1
                                                    ;;
        --apigatewayMetricsEnabled )                shift
                                                    apigatewayMetricsEnabled=$1
                                                    ;;
        --apigatewayLatencyThreshold )              shift
                                                    apigatewayLatencyThreshold=$1
                                                    ;;
        --apigatewayServerErrorThreshold )          shift
                                                    apigatewayServerErrorThreshold=$1
                                                    ;;
        --apigatewayClientErrorThreshold )          shift
                                                    apigatewayClientErrorThreshold=$1
                                                    ;;
        --lambdaErrorThreshold )                    shift
                                                    lambdaErrorThreshold=$1
                                                    ;;
        --ddbToESLambdaErrorThreshold )             shift
                                                    ddbToESLambdaErrorThreshold=$1
                                                    ;;                                        
        -h | --help )                               usage
                                                    exit
                                                    ;;
        * )                                         usage
                                                    exit 1
    esac
    shift
done

clear

command -v aws >/dev/null 2>&1 || { echo >&2 "AWS CLI cannot be found. Please install or check your PATH.  Aborting."; exit 1; }

if ! `aws sts get-caller-identity >/dev/null 2>&1`; then
    echo "Could not find any valid AWS credentials. You can configure credentials by running 'aws configure'. If running this script with sudo you must configure your awscli with 'sudo aws configure'"
    echo "For more information about configuring the AWS CLI see: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html"
    echo ""
    exit 1;
fi

echo -e "\nFound AWS credentials for the following User/Role:\n"
aws sts get-caller-identity
echo -e "\n"

if ! `YesOrNo "Is this the correct User/Role for this deployment?"`; then
  exit 1
fi

#Check to make sure the server isn't already deployed
already_deployed=false
redep=`aws cloudformation describe-stacks --stack-name fhir-service-smart-$stage --region $region --output text 2>&1` && already_deployed=true
if $already_deployed; then
    if `echo "$redep" | grep -Fxq "DELETE_FAILED"`; then
        fail=true
        echo "ERROR: FHIR Server already exists, but it seems to be corrupted."
        echo -e "Would you like to redeploy the FHIR Server?\n"
    else
        fail=false
        echo "FHIR Server already exists!"
        echo -e "Would you like to remove the current server and redeploy?\n"
    fi

    if `YesOrNo "Do you want to continue with redeployment?"`; then
        echo -e "\nOkay, let's redeploy the server.\n"
    else
        if ! $fail; then
            eval $( parse_log Info_Output.log )
            echo -e "\n\nSetup completed successfully."
            echo -e "You can now access the FHIR APIs directly or through a service like POSTMAN.\n\n"
            echo "For more information on setting up POSTMAN, please see the README file."
            echo -e "All user details were stored in 'Info_Output.log'.\n"
        fi
        exit 1
    fi
fi

echo -e "Setup will proceed with the following parameters: \n"
echo "  Issuer Endpoint: $issuerEndpoint"
echo "  OAuth2 API Endpoint: $oAuth2ApiEndpoint"
echo "  Patient Picker Endpoint: $patientPickerEndpoint"
echo "  Stage: $stage"
echo "  Region: $region"
echo "  lambdaLatencyThreshold: $lambdaLatencyThreshold"
echo "  apigatewayMetricsEnabled: $apigatewayMetricsEnabled"
echo "  apigatewayLatencyThreshold: $apigatewayLatencyThreshold"
echo "  apigatewayServerErrorThreshold: $apigatewayServerErrorThreshold"
echo "  apigatewayClientErrorThreshold: $apigatewayClientErrorThreshold"
echo "  lambdaErrorThreshold: $lambdaErrorThreshold"
echo "  ddbToESLambdaErrorThreshold: $ddbToESLambdaErrorThreshold"
echo "  alarmSubscriptionEndpoint: $alarmSubscriptionEndpoint"
echo ""

if ! `YesOrNo "Are these settings correct?"`; then
    echo ""
    usage
    exit 1
fi

if [ "$DOCKER" != "true" ]; then
    echo -e "\nIn order to deploy the server, the following dependencies are required:"
    echo -e "\t- nodejs\n\t- npm\n\t- python3\n\t- yarn"
    echo -e "\nThese dependencies will be installed (if not already present)."
    if ! `YesOrNo "Would you like to continue?"`; then
        echo "Exiting..."
        exit 1
    fi

    echo -e "\nInstalling dependencies...\n"
    install_dependencies
    result=$?
    if [ "$result" != "0" ]; then
        echo ${error_msg}
        exit 1
    fi
    echo "Done!"
fi

IAMUserARN=$(aws sts get-caller-identity --query "Arn" --output text)

#TODO: how to stop if not all test cases passed?
cd ${PACKAGE_ROOT}
yarn install --frozen-lockfile
yarn run release

touch serverless_config.json
if ! grep -Fq "devAwsUserAccountArn" serverless_config.json; then
    echo -e "{\n  \"devAwsUserAccountArn\": \"$IAMUserARN\"\n}" >> serverless_config.json
fi

# need to import private api gateway resources into cfn
if [[ "${IMPORT_PRIVATE_API_GATEWAY}" == "true" ]]; then
    echo "Importing private API gateway resources and methods into the fhir-service$smartTag-$stage cloudformation stack"

    # 4 different states to address here
    # 1. Fresh install - will not have a cloudformation stack yet and we need to do a serverless deploy w/import = false
    # 2. version w/o private API gateway - stack will exist but private api gateway resources will not have physical IDs
    # 3. version w/private API - stack will exist but private API gateway resource will not exist in stack
    # 4. already imported - stack will exist, resources will exist and have both logical and physical IDs
    
    # check for fresh install
    stack_exists=$(aws cloudformation list-stacks | jq -e -r --arg stack_name "fhir-service$smartTag-$stage" '.StackSummaries[] | select(.StackName == $stack_name and .StackStatus != "DELETE_COMPLETE" and .StackStatus != "DELETE_IN_PROGRESS") | has("StackId")')
    if [ "$stack_exists" != true ]; then
        # okay so a fresh install will need the stack deployed w/import = false to do the initial cloneFrom
        
        echo "Fresh install so creating private API gateway using cloneFrom"
        echo "starting cloneFrom deploy...."
        LAMBDA_LATENCY_THRESHOLD=$lambdaLatencyThreshold \
        APIGATEWAY_LATENCY_THRESHOLD=$apigatewayLatencyThreshold \
        APIGATEWAY_SERVER_ERROR_THRESHOLD=$apigatewayServerErrorThreshold \
        APIGATEWAY_CLIENT_ERROR_THRESHOLD=$apigatewayClientErrorThreshold \
        LAMBDA_ERROR_THRESHOLD=$lambdaErrorThreshold \
        DDB_TO_ES_LAMBDA_ERROR_THRESHOLD=$ddbToESLambdaErrorThreshold \
        ALARM_SUBSCRIPTION_ENDPOINT=$alarmSubscriptionEndpoint \
        APIGATEWAY_METRICS_ENABLED=$apigatewayMetricsEnabled \
        ENABLE_PRIVATE_API_GATEWAY="true" \
        IMPORT_PRIVATE_API_GATEWAY="false" \
        yarn run serverless-deploy --region $region --stage $stage --issuerEndpoint $issuerEndpoint --oAuth2ApiEndpoint $oAuth2ApiEndpoint --patientPickerEndpoint $patientPickerEndpoint || { echo >&2 "Failed to deploy serverless application."; exit 1; }
        echo "completed cloneFrom deploy...."
    else
        echo "found existing deployment, skipping cloneFrom private API gateway serverless deploy"
    fi

    echo "getting cloud formation template"
    aws cloudformation get-template --stack-name "fhir-service$smartTag-$stage" | jq '.TemplateBody' > /tmp/fhir_service_template.json

    # check if we've deployed before but w/o a cloneFrom run
    has_private_api_gateway=$(cat /tmp/fhir_service_template.json | jq -e -r '.Resources | has("FHIRServicePrivate")')
    if [ "$has_private_api_gateway" != true ]; then
        echo "existing install but no private API gateway"
        echo "starting cloneFrom deploy...."
        LAMBDA_LATENCY_THRESHOLD=$lambdaLatencyThreshold \
        APIGATEWAY_LATENCY_THRESHOLD=$apigatewayLatencyThreshold \
        APIGATEWAY_SERVER_ERROR_THRESHOLD=$apigatewayServerErrorThreshold \
        APIGATEWAY_CLIENT_ERROR_THRESHOLD=$apigatewayClientErrorThreshold \
        LAMBDA_ERROR_THRESHOLD=$lambdaErrorThreshold \
        DDB_TO_ES_LAMBDA_ERROR_THRESHOLD=$ddbToESLambdaErrorThreshold \
        ALARM_SUBSCRIPTION_ENDPOINT=$alarmSubscriptionEndpoint \
        APIGATEWAY_METRICS_ENABLED=$apigatewayMetricsEnabled \
        ENABLE_PRIVATE_API_GATEWAY="true" \
        IMPORT_PRIVATE_API_GATEWAY="false" \
        yarn run serverless-deploy --region $region --stage $stage --issuerEndpoint $issuerEndpoint --oAuth2ApiEndpoint $oAuth2ApiEndpoint --patientPickerEndpoint $patientPickerEndpoint || { echo >&2 "Failed to deploy serverless application."; exit 1; }
        echo "completed cloneFrom deploy...."
    else
        echo "private api gateway already deployed with cloneFrom"
    fi

    resources=(
        "FHIRServicePrivateApiGatewayMethodAny"
        "FHIRServicePrivateApiGatewayResourceMetadata"
        "FHIRServicePrivateApiGatewayMethodMetadataGet"
        "FHIRServicePrivateApiGatewayResourceProxyVar"
        "FHIRServicePrivateApiGatewayMethodProxyVarAny"
    )
    has_resources=false
    echo "checking cloudformation template for private api gateway resources"
    for i in "${resources[@]}"
    do
        has_resource=$(cat /tmp/fhir_service_template.json | jq --arg resource_id "$i" '.Resources | has($resource_id)')
        if [ "$has_resource" = true ]; then
            echo "found private api gateway resource $i in cloudformation template"
            has_resources=true
        else
            echo "did not find private api gateway resource $i in cloudformation template"
        fi
    done

    if [ "$has_resources" = true ]; then
        echo "cloudformation template already contains private API gateway resources. checking if physical IDs exist"
        for i in "${resources[@]}"
        do
            has_physical_id=$(aws cloudformation describe-stack-resource --logical-resource-id "$i" --stack-name "fhir-service$smartTag-$stage" | jq -e -r '.StackResourceDetail | has("PhysicalResourceId")')
            if [ "$has_physical_id" != true ]; then
                # we need to remove the resources from the template for import

                echo "found private API gateway resource $i without a physical ID"
                resource_path=".Resources.$i"
                cat /tmp/fhir_service_template.json | jq --arg resource "$resource_path" 'del($resource)' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json
                has_resources=false
            else
                echo "physical ID found for $i"
            fi

            if [ "$has_resources" = false ]; then
                # need to update the cfn template to no longer include the resources w/o physical IDs so we can import
                echo "uploading new cloudformation template to s3 for update to remove private API gateway resources w/o physical IDs"
                aws s3 cp \
                    "/tmp/fhir_service_template.json" \
                    "s3://${IMPORT_PRIVATE_API_GATEWAY_BUCKET}/cloudformation_templates/"

                # create update changeset
                echo "creating cloudformation changeset to remove private API gateway resources w/o physical IDs"
                aws cloudformation create-change-set \
                    --stack-name "fhir-service$smartTag-$stage" \
                    --change-set-name "UpdateChangeSet" \
                    --change-set-type "UPDATE" \
                    --template-url "https://${IMPORT_PRIVATE_API_GATEWAY_BUCKET}.s3.${region}.amazonaws.com/cloudformation_templates/fhir_service_template.json" \
                    --capabilities "CAPABILITY_IAM"

                # wait for changeset to be in a ready state for execution
                wait_for_cfn_changeset "UpdateChangeSet" "AVAILABLE"
                
                # execute changeset
                echo "executing cloudformation changeset to remove private API gateway resources w/o physical IDs"
                aws cloudformation execute-change-set \
                    --change-set-name "UpdateChangeSet" \
                    --stack-name "fhir-service$smartTag-$stage"

                # wait for changeset to be executed
                wait_for_cfn_changeset "UpdateChangeSet" "EXECUTE_COMPLETE"
            fi
        done
    fi

    # check for a deployment w/o private API gateway resource physical IDs
    if [ "$has_resources" = false ]; then
        echo "existing stack does not have private api gateway resources. starting import..."

        # get the private api gateway ID
        PRIVATE_API_GATEWAY_ID=$(aws apigateway get-rest-apis | jq -r --arg private_ag_name "${stage}-fhir-service-private" '.items[] | select(.name == $private_ag_name) |  .id' )

        # get the resource IDs for root, metadata and {proxy+}
        PRIVATE_API_GATEWAY_ROOT_ID=$(aws apigateway get-resources --rest-api-id ${PRIVATE_API_GATEWAY_ID} | jq -r '.items[] | select(.path == "/") | .id')
        PRIVATE_API_GATEWAY_METADATA_ID=$(aws apigateway get-resources --rest-api-id ${PRIVATE_API_GATEWAY_ID} | jq -r '.items[] | select(.path == "/metadata") | .id')
        PRIVATE_API_GATEWAY_PROXY_ID=$(aws apigateway get-resources --rest-api-id ${PRIVATE_API_GATEWAY_ID} | jq -r '.items[] | select(.path == "/{proxy+}") | .id')

        echo "found the following IDs:"
        echo "PRIVATE_API_GATEWAY_ID=${PRIVATE_API_GATEWAY_ID}"
        echo "PRIVATE_API_GATEWAY_ROOT_ID=${PRIVATE_API_GATEWAY_ROOT_ID}"
        echo "PRIVATE_API_GATEWAY_METADATA_ID=${PRIVATE_API_GATEWAY_METADATA_ID}"
        echo "PRIVATE_API_GATEWAY_PROXY_ID=${PRIVATE_API_GATEWAY_PROXY_ID}"

        # need to add the resources we want to import to the template
        cat /tmp/fhir_service_template.json | jq '.Resources +={"FHIRServicePrivateApiGatewayMethodAny":{"Type":"AWS::ApiGateway::Method","DeletionPolicy":"Delete","Condition":"isUsingPrivateApi","Properties":{"HttpMethod":"ANY","RequestParameters":{},"ResourceId":{"Fn::GetAtt":["FHIRServicePrivate","RootResourceId"]},"RestApiId":{"Ref":"FHIRServicePrivate"},"ApiKeyRequired":true,"AuthorizationType":"NONE","Integration":{"IntegrationHttpMethod":"POST","Type":"AWS_PROXY","Uri":{"Fn::Join":["",["arn:",{"Ref":"AWS::Partition"},":apigateway:",{"Ref":"AWS::Region"},":lambda:path/2015-03-31/functions/",{"Fn::GetAtt":["FhirServerLambdaFunction","Arn"]},":","provisioned","/invocations"]]}},"MethodResponses":[]},"DependsOn":["FHIRServicePrivateLambdaPermission"]}}' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json
        cat /tmp/fhir_service_template.json | jq -r '.Resources +={"FHIRServicePrivateApiGatewayResourceMetadata":{"Type":"AWS::ApiGateway::Resource","DeletionPolicy":"Delete","Condition":"isUsingPrivateApi","Properties":{"ParentId":{"Fn::GetAtt":["FHIRServicePrivate","RootResourceId"]},"PathPart":"metadata","RestApiId":{"Ref":"FHIRServicePrivate"}}}}' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json
        cat /tmp/fhir_service_template.json | jq -r '.Resources +={"FHIRServicePrivateApiGatewayMethodMetadataGet":{"Type":"AWS::ApiGateway::Method","DeletionPolicy":"Delete","Condition":"isUsingPrivateApi","Properties":{"HttpMethod":"GET","RequestParameters":{},"ResourceId":{"Ref":"FHIRServicePrivateApiGatewayResourceMetadata"},"RestApiId":{"Ref":"FHIRServicePrivate"},"ApiKeyRequired":false,"AuthorizationType":"NONE","Integration":{"IntegrationHttpMethod":"POST","Type":"AWS_PROXY","Uri":{"Fn::Join":["",["arn:",{"Ref":"AWS::Partition"},":apigateway:",{"Ref":"AWS::Region"},":lambda:path/2015-03-31/functions/",{"Fn::GetAtt":["FhirServerLambdaFunction","Arn"]},":","provisioned","/invocations"]]}},"MethodResponses":[]},"DependsOn":["FHIRServicePrivateLambdaPermission"],"Metadata":{"cfn_nag":{"rules_to_suppress":[{"id":"W45","reason":"This API endpoint should not require authentication (due to the FHIR spec)"}]}}}}' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json
        cat /tmp/fhir_service_template.json | jq -r '.Resources +={"FHIRServicePrivateApiGatewayResourceProxyVar":{"Type":"AWS::ApiGateway::Resource","DeletionPolicy":"Delete","Condition":"isUsingPrivateApi","Properties":{"ParentId":{"Fn::GetAtt":["FHIRServicePrivate","RootResourceId"]},"PathPart":"{proxy+}","RestApiId":{"Ref":"FHIRServicePrivate"}}}}' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json
        cat /tmp/fhir_service_template.json | jq -r '.Resources +={"FHIRServicePrivateApiGatewayMethodProxyVarAny":{"Type":"AWS::ApiGateway::Method","DeletionPolicy":"Delete","Condition":"isUsingPrivateApi","Properties":{"HttpMethod":"ANY","RequestParameters":{},"ResourceId":{"Ref":"FHIRServicePrivateApiGatewayResourceProxyVar"},"RestApiId":{"Ref":"FHIRServicePrivate"},"ApiKeyRequired":true,"AuthorizationType":"NONE","Integration":{"IntegrationHttpMethod":"POST","Type":"AWS_PROXY","Uri":{"Fn::Join":["",["arn:",{"Ref":"AWS::Partition"},":apigateway:",{"Ref":"AWS::Region"},":lambda:path/2015-03-31/functions/",{"Fn::GetAtt":["FhirServerLambdaFunction","Arn"]},":","provisioned","/invocations"]]}},"MethodResponses":[]},"DependsOn":["FHIRServicePrivateLambdaPermission"]}}' > /tmp/fhir_service_template.json.tmp && mv /tmp/fhir_service_template.json.tmp /tmp/fhir_service_template.json

        # upload template to s3
        echo "uploading new cloudformation template to s3"
        aws s3 cp /tmp/fhir_service_template.json s3://${IMPORT_PRIVATE_API_GATEWAY_BUCKET}/cloudformation_templates/

        # create resources to import document
        RESOURCES_TO_IMPORT=$(jq --null-input \
            --arg private_api_gateway_id "${PRIVATE_API_GATEWAY_ID}" \
            --arg private_api_gateway_root_id "${PRIVATE_API_GATEWAY_ROOT_ID}" \
            --arg private_api_gateway_metadata_id "${PRIVATE_API_GATEWAY_METADATA_ID}" \
            --arg private_api_gateway_proxy_id "${PRIVATE_API_GATEWAY_PROXY_ID}" \
            '[{"ResourceType":"AWS::ApiGateway::Method","LogicalResourceId":"FHIRServicePrivateApiGatewayMethodAny","ResourceIdentifier":{"RestApiId":$private_api_gateway_id,"ResourceId":$private_api_gateway_root_id,"HttpMethod":"ANY"}},{"ResourceType":"AWS::ApiGateway::Resource","LogicalResourceId":"FHIRServicePrivateApiGatewayResourceMetadata","ResourceIdentifier":{"RestApiId":$private_api_gateway_id,"ResourceId":$private_api_gateway_metadata_id}},{"ResourceType":"AWS::ApiGateway::Method","LogicalResourceId":"FHIRServicePrivateApiGatewayMethodMetadataGet","ResourceIdentifier":{"RestApiId":$private_api_gateway_id,"ResourceId":$private_api_gateway_metadata_id,"HttpMethod":"GET"}},{"ResourceType":"AWS::ApiGateway::Resource","LogicalResourceId":"FHIRServicePrivateApiGatewayResourceProxyVar","ResourceIdentifier":{"RestApiId":$private_api_gateway_id,"ResourceId":$private_api_gateway_proxy_id}},{"ResourceType":"AWS::ApiGateway::Method","LogicalResourceId":"FHIRServicePrivateApiGatewayMethodProxyVarAny","ResourceIdentifier":{"RestApiId":$private_api_gateway_id,"ResourceId":$private_api_gateway_proxy_id,"HttpMethod":"ANY"}}]')

        echo "RESOURCES_TO_IMPORT JSON:"
        echo "${RESOURCES_TO_IMPORT}"

        # create changeset
        aws cloudformation create-change-set \
            --stack-name "fhir-service$smartTag-$stage" \
            --change-set-name "ImportChangeSet" \
            --change-set-type "IMPORT" \
            --resources-to-import "${RESOURCES_TO_IMPORT}" \
            --template-url "https://${IMPORT_PRIVATE_API_GATEWAY_BUCKET}.s3.${region}.amazonaws.com/cloudformation_templates/fhir_service_template.json" \
            --capabilities CAPABILITY_IAM

        
        # wait for changeset to be in a ready state for executeion
        wait_for_cfn_changeset "ImportChangeSet" "AVAILABLE"
        
        # execute changeset
        aws cloudformation execute-change-set --change-set-name ImportChangeSet --stack-name "fhir-service-${stage}"
        wait_for_cfn_changeset "ImportChangeSet" "EXECUTE_COMPLETE"

        # curse cloudformation's name
        # cfn!??!?!
    else
        echo "Already imported private API gateway methods and resources"
    fi  
fi 

echo -e "\n\nFHIR Works is deploying. A fresh install will take ~20 mins\n\n"
## Deploy to stated region
LAMBDA_LATENCY_THRESHOLD=$lambdaLatencyThreshold \
APIGATEWAY_LATENCY_THRESHOLD=$apigatewayLatencyThreshold \
APIGATEWAY_SERVER_ERROR_THRESHOLD=$apigatewayServerErrorThreshold \
APIGATEWAY_CLIENT_ERROR_THRESHOLD=$apigatewayClientErrorThreshold \
LAMBDA_ERROR_THRESHOLD=$lambdaErrorThreshold \
DDB_TO_ES_LAMBDA_ERROR_THRESHOLD=$ddbToESLambdaErrorThreshold \
ALARM_SUBSCRIPTION_ENDPOINT=$alarmSubscriptionEndpoint \
APIGATEWAY_METRICS_ENABLED=$apigatewayMetricsEnabled \
yarn run serverless-deploy --region $region --stage $stage --issuerEndpoint $issuerEndpoint --oAuth2ApiEndpoint $oAuth2ApiEndpoint --patientPickerEndpoint $patientPickerEndpoint || { echo >&2 "Failed to deploy serverless application."; exit 1; }

## Output to console and to file Info_Output.log.  tee not used as it removes the output highlighting.
echo -e "Deployed Successfully.\n"
touch Info_Output.log
SLS_DEPRECATION_DISABLE=* yarn run serverless-info --verbose --region $region --stage $stage && SLS_DEPRECATION_DISABLE=* yarn run serverless-info --verbose --region $region --stage $stage > Info_Output.log
#The double call to serverless info was a bugfix from Steven Johnston
    #(may not be needed)

#Read in variables from Info_Output.log
eval $( parse_log Info_Output.log )

# #Set up Cognito user for Kibana server (only created if stage is dev)
if [ $stage == 'dev' ]; then
    echo "In order to be able to access the Kibana server for your ElasticSearch Service Instance, you need create a cognito user."
    echo -e "You can set up a cognito user automatically through this install script, \nor you can do it manually via the Cognito console.\n"
    while `YesOrNo "Do you want to set up a cognito user now?"`; do
        echo ""
        echo "Okay, we'll need to create a cognito user using an email address and password."
        echo ""
        read -p "Enter your email address (<youremail@address.com>): " cognitoUsername
        echo -e "\n"
        if `YesOrNo "Is $cognitoUsername your correct email?"`; then
            echo -e "\n\nPlease create a temporary password. Passwords must satisfy the following requirements: "
            echo "  * 8-20 characters long"
            echo "  * at least 1 lowercase character"
            echo "  * at least 1 uppercase character"
            echo "  * at least 1 special character (Any of the following: '!@#$%^\&*()[]_+-\")"
            echo "  * at least 1 number character"
            echo ""
            temp_cognito_p=`get_valid_pass`
            echo ""
            aws cognito-idp sign-up \
              --region "$region" \
              --client-id "$ElasticSearchKibanaUserPoolAppClientId" \
              --username "$cognitoUsername" \
              --password "$temp_cognito_p" \
              --user-attributes Name="email",Value="$cognitoUsername" &&
            echo -e "\nSuccess: Created a cognito user.\n\n \
                    You can now log into the Kibana server using the email address you provided (username) and your temporary password.\n \
                    You may have to verify your email address before logging in.\n \
                    The URL for the Kibana server can be found in ./Info_Output.log in the 'ElasticSearchDomainKibanaEndpoint' entry.\n\n \
                    This URL will also be copied below:\n \
                    $ElasticSearchDomainKibanaEndpoint"
            break
        else
            echo -e "\nSorry about that--let's start over.\n"
        fi
    done
fi
cd ${PACKAGE_ROOT}
##Cloudwatch audit log mover

echo -e "\n\nAudit Logs are placed into CloudWatch Logs at <CLOUDWATCH_EXECUTION_LOG_GROUP>. \
The Audit Logs includes information about request/responses coming to/from your API Gateway. \
It also includes the user that made the request."

echo -e "\nYou can also set up the server to archive logs older than 7 days into S3 and delete those logs from Cloudwatch Logs."
echo "You can also do this later manually, if you would prefer."
echo ""
if `YesOrNo "Would you like to set the server to archive logs older than 7 days?"`; then
    cd ${PACKAGE_ROOT}/auditLogMover
    yarn install --frozen-lockfile
    ALARM_SUBSCRIPTION_ENDPOINT=$alarmSubscriptionEndpoint \
    yarn run serverless-deploy --region $region --stage $stage
    cd ${PACKAGE_ROOT}
    echo -e "\n\nSuccess."
fi


#DynamoDB Table Backups
echo -e "\n\nWould you like to set up daily DynamoDB Table backups?\n"
echo "Selecting 'yes' below will set up backups using the default setup from the cloudformation/backups.yaml file."
echo -e "DynamoDB Table backups can also be set up later. See the README file for more information.\n"
echo "Note: This will deploy an additional stack, and can lead to increased costs to run this server."
echo ""
if `YesOrNo "Would you like to set up backups now?"`; then
    cd ${PACKAGE_ROOT}
    aws cloudformation create-stack --stack-name fhir-server-backups \
    --template-body file://cloudformation/backup.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $region
    echo "DynamoDB Table backups are being deployed. Please validate status of CloudFormation stack"
    echo "fhir-server-backups in ${region} region."
    echo "Backups are configured to be automatically performed at 5:00 UTC, if deployment succeeded."
fi


echo -e "\n\nSetup completed successfully."
echo -e "You can now access the FHIR APIs directly or through a service like POSTMAN.\n\n"
echo "For more information on setting up POSTMAN, please see the README file."
echo -e "All user details were stored in 'Info_Output.log'.\n"
