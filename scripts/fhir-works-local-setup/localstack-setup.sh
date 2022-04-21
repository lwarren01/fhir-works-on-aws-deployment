#!/usr/bin/env bash

docker-compose up --detach

sleep 5

# Set up the required AWS resources in local stack

awslocal ssm put-parameter --name "/dev/fhirworks-auth-issuer-endpoint" --value "dummy" --type="String"

awslocal dynamodb create-table --cli-input-json file://create-resource-table.json --region us-east-1

#start serverless offline

cd ../..

serverless offline start


# To stop the localstack services, run 'docker-compose down' in a terminal
