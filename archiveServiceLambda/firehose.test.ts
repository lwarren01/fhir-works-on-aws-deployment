import AWS from 'aws-sdk';
import sinon from 'sinon';
import AWSMock from 'aws-sdk-mock';
import _ from 'lodash';
import firehose from './firehose';

const sandbox = sinon.createSandbox();
const putRecordBatchStub = sandbox.stub();
const consoleLogStub = sandbox.stub();
AWSMock.setSDKInstance(AWS);

// TODO: create test builders
const DEFAULT_RECORD_EVENT = {
    eventID: 'b6f38f0ff74096f159d2837024b2bfe3',
    eventName: 'REMOVE',
    eventVersion: '1.1',
    eventSource: 'aws:dynamodb',
    awsRegion: 'us-west-2',
    dynamodb: {
        ApproximateCreationDateTime: 1619625698,
        Keys: {
            vid: {
                N: '1',
            },
            id: {
                S: 'a87babae-22cc-4189-919f-fcfe3ec656ff',
            },
        },
        OldImage: {
            agent: {
                L: [
                    {
                        M: {
                            name: {
                                S: 'My Agent Name',
                            },
                            requestor: {
                                BOOL: true,
                            },
                        },
                    },
                ],
            },
            source: {
                M: {
                    observer: {
                        M: {
                            id: {
                                S: 'f1d8e233-6c7b-4265-b18f-af286820158b',
                            },
                        },
                    },
                },
            },
            _references: {
                L: [],
            },
            recorded: {
                S: '2021-04-15T17:31:50.627Z',
            },
            type: {
                M: {
                    system: {
                        S: 'http://fhir.example.com',
                    },
                },
            },
            ttl: {
                N: '1619625026',
            },
            lockEndTs: {
                N: '1619624966772',
            },
            vid: {
                N: '1',
            },
            meta: {
                M: {
                    lastUpdated: {
                        S: '2021-04-28T15:49:26.772Z',
                    },
                    versionId: {
                        S: '1',
                    },
                },
            },
            documentStatus: {
                S: 'AVAILABLE',
            },
            id: {
                S: 'a87babae-22cc-4189-919f-fcfe3ec656ff',
            },
            entity: {
                L: [
                    {
                        M: {
                            lifecycle: {
                                M: {
                                    system: {
                                        S: 'http://terminology.hl7.org/CodeSystem/dicom-audit-lifecycle',
                                    },
                                    code: {
                                        S: '6',
                                    },
                                    display: {
                                        S: 'Access / Use',
                                    },
                                },
                            },
                            what: {
                                M: {
                                    identifier: {
                                        M: {
                                            type: {
                                                M: {
                                                    coding: {
                                                        L: [
                                                            {
                                                                M: {
                                                                    system: {
                                                                        S: 'http://terminology.hl7.org/CodeSystem/v2-0203',
                                                                    },
                                                                    code: {
                                                                        S: 'SNO',
                                                                    },
                                                                },
                                                            },
                                                        ],
                                                    },
                                                    text: {
                                                        S: 'Dell Serial Number',
                                                    },
                                                },
                                            },
                                            value: {
                                                S: 'ABCDEF',
                                            },
                                        },
                                    },
                                },
                            },
                            role: {
                                M: {
                                    system: {
                                        S: 'http://terminology.hl7.org/CodeSystem/object-role',
                                    },
                                    code: {
                                        S: '4',
                                    },
                                    display: {
                                        S: 'Domain Resource',
                                    },
                                },
                            },
                            name: {
                                S: "Grahame's Laptop",
                            },
                            type: {
                                M: {
                                    system: {
                                        S: 'http://terminology.hl7.org/CodeSystem/audit-entity-type',
                                    },
                                    code: {
                                        S: '4',
                                    },
                                    display: {
                                        S: 'Other',
                                    },
                                },
                            },
                        },
                    },
                ],
            },
            resourceType: {
                S: 'AuditEvent',
            },
        },
        SequenceNumber: '75067200000000010290539606',
        SizeBytes: 844,
        StreamViewType: 'NEW_AND_OLD_IMAGES',
    },
    userIdentity: {
        principalId: 'dynamodb.amazonaws.com',
        type: 'Service',
    },
    eventSourceARN: 'arn:aws:dynamodb:us-west-2:1234567890123:table/resource-db-dev/stream/2021-04-12T19:25:18.997',
};

describe('firehose putRecords', () => {
    beforeEach(() => {
        AWSMock.mock('Firehose', 'putRecordBatch', putRecordBatchStub);
        sandbox.replace(console, 'log', consoleLogStub);
        putRecordBatchStub.reset();
    });

    afterEach(() => {
        AWSMock.restore();
        sandbox.restore();
    });

    test('putRecordBatch fails', async () => {
        putRecordBatchStub.yields(new Error('AWS Firehose.putRecordBatch call failed'), null);
        const event = {
            Records: [_.cloneDeep(DEFAULT_RECORD_EVENT)],
        };

        await firehose.putRecords(event.Records);

        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing sad songs,')).toEqual(true);
    });

    test('partial payload failures in batch logged', async () => {
        putRecordBatchStub.yields(null, {
            FailedPutCount: 1,
            Encrypted: true,
            RequestResponses: [
                {
                    RecordId: Math.random().toString(16).substring(2),
                },
                {
                    RecordId: Math.random().toString(16).substring(2),
                    ErrorCode: Math.random().toString(16).substring(2),
                    ErrorMessage: 'Stuff done broke',
                },
            ],
        });

        const event = {
            Records: [_.cloneDeep(DEFAULT_RECORD_EVENT), _.cloneDeep(DEFAULT_RECORD_EVENT)],
        };

        await firehose.putRecords(event.Records);

        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing sad songs,')).toEqual(true);
    });

    test('all pass', async () => {
        putRecordBatchStub.yields(null, {
            FailedPutCount: 0,
            Encrypted: true,
            RequestResponses: [
                {
                    RecordId: Math.random().toString(16).substring(2),
                },
                {
                    RecordId: Math.random().toString(16).substring(2),
                },
            ],
        });

        const event = {
            Records: [_.cloneDeep(DEFAULT_RECORD_EVENT), _.cloneDeep(DEFAULT_RECORD_EVENT)],
        };

        await firehose.putRecords(event.Records);

        expect(consoleLogStub.lastCall.firstArg).toEqual('sing happy songs, 2 records pushed to delivery stream');
        expect(_.startsWith(consoleLogStub.lastCall.firstArg, 'sing happy songs,')).toEqual(true);
    });
});
