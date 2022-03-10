import AWS from 'aws-sdk';
import sinon from 'sinon';
import AWSMock from 'aws-sdk-mock';
import _ from 'lodash';
import dynamodb from './dynamodb';

const sandbox = sinon.createSandbox();
const batchExecuteStatementStub = sandbox.stub();
const consoleLogStub = sandbox.stub();
AWSMock.setSDKInstance(AWS);

// TODO: create test builders
const DEFAULT_RECORD_EVENT = {
    eventID: '1a3e49152e5fe9f1e5842c17f615d771',
    eventName: 'INSERT',
    eventVersion: '1.1',
    eventSource: 'aws:dynamodb',
    awsRegion: 'us-west-2',
    dynamodb: {
        ApproximateCreationDateTime: 1647264242,
        Keys: {
            vid: {
                N: '1',
            },
            id: {
                S: '5d431a2a-be00-41b5-9cff-111265b2d9a5',
            },
        },
        NewImage: {
            identifier: {
                L: [
                    {
                        M: {
                            value: {
                                S: 'QE2-Halifax',
                            },
                        },
                    },
                ],
            },
            address: {
                L: [
                    {
                        M: {
                            country: {
                                S: 'Canada',
                            },
                            city: {
                                S: 'Halifax',
                            },
                            postalCode: {
                                S: 'B4BC3C',
                            },
                            state: {
                                S: 'NS',
                            },
                        },
                    },
                ],
            },
            gender: {
                S: 'male',
            },
            active: {
                BOOL: true,
            },
            _references: {
                L: [
                    {
                        S: 'Organization/19d9bd55-56fc-4d19-850f-2c1ee651aefb',
                    },
                ],
            },
            birthDate: {
                S: '1996-09-24',
            },
            lockEndTs: {
                N: '1647264242065',
            },
            vid: {
                N: '1',
            },
            managingOrganization: {
                M: {
                    reference: {
                        S: 'Organization/19d9bd55-56fc-4d19-850f-2c1ee651aefb',
                    },
                },
            },
            meta: {
                M: {
                    lastUpdated: {
                        S: '2022-03-14T13:24:02.065Z',
                    },
                    versionId: {
                        S: '1',
                    },
                },
            },
            name: {
                L: [
                    {
                        M: {
                            given: {
                                L: [
                                    {
                                        S: 'IWK',
                                    },
                                ],
                            },
                            family: {
                                S: '6',
                            },
                        },
                    },
                ],
            },
            documentStatus: {
                S: 'AVAILABLE',
            },
            id: {
                S: '5d431a2a-be00-41b5-9cff-111265b2d9a5',
            },
            resourceType: {
                S: 'Patient',
            },
        },
        SequenceNumber: '46107900000000048533287743',
        SizeBytes: 512,
        StreamViewType: 'NEW_AND_OLD_IMAGES',
    },
    eventSourceARN: 'arn:aws:dynamodb:us-west-2:325115894113:table/resource-db-dev/stream/2022-03-04T20:48:00.152',
};

const DEFAULT_TTL_IN_SECONDS = new Map();
DEFAULT_TTL_IN_SECONDS.set('Patient', '150000');

describe('dynamodb updateRecords', () => {
    beforeEach(() => {
        AWSMock.mock('DynamoDB', 'batchExecuteStatement', batchExecuteStatementStub);
        sandbox.replace(console, 'log', consoleLogStub);
        batchExecuteStatementStub.reset();
    });

    afterEach(() => {
        AWSMock.restore();
        sandbox.restore();
    });

    test('updateRecords fails', async () => {
        batchExecuteStatementStub.yields(new Error('AWS DynamoDB.batchExecuteStatement call failed'), null);
        const records = [_.cloneDeep(DEFAULT_RECORD_EVENT)];
        await dynamodb.updateRecords(records, DEFAULT_TTL_IN_SECONDS);

        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing sad songs,')).toEqual(true);
    });

    test('partial payload failures in batch logged', async () => {
        batchExecuteStatementStub.yields(null, {
            Responses: [
                {
                    TableName: 'resource-db-dev',
                },
                {
                    Error: {
                        Code: 'ValidationError',
                    },
                    TableName: 'resource-db-dev',
                },
            ],
        });

        const records = [_.cloneDeep(DEFAULT_RECORD_EVENT), _.cloneDeep(DEFAULT_RECORD_EVENT)];
        await dynamodb.updateRecords(records, DEFAULT_TTL_IN_SECONDS);

        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing sad songs,')).toEqual(true);
    });

    test('all pass', async () => {
        batchExecuteStatementStub.yields(null, {
            Responses: [
                {
                    TableName: 'resource-db-dev',
                },
                {
                    TableName: 'resource-db-dev',
                },
            ],
        });

        const records = [_.cloneDeep(DEFAULT_RECORD_EVENT), _.cloneDeep(DEFAULT_RECORD_EVENT)];
        await dynamodb.updateRecords(records, DEFAULT_TTL_IN_SECONDS);

        expect(consoleLogStub.lastCall.firstArg).toEqual('sing happy songs, 2 items are updated');
        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing happy songs,')).toEqual(true);
    });
});
