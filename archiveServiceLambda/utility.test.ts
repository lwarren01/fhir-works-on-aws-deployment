import utility from './utility';
import dynamodb from './dynamodb';

describe('parse environment variable ARCHIVE_CONFIG', () => {
    test('archive config is not defined', () => {
        const expected = new Map<string, number>();

        expect(utility.parseArchiveConfig(undefined)).toEqual(expected);
    });

    test('archive config is empty string', () => {
        const expected = new Map<string, number>();

        expect(utility.parseArchiveConfig(' ')).toEqual(expected);
    });

    test('single archive config is provided', () => {
        const expected = new Map<string, number>();
        const resourceType = 'AuditEvent';
        const ttlInSeconds = 15780000;
        expected.set(resourceType, ttlInSeconds);
        expect(utility.parseArchiveConfig(`${resourceType},${ttlInSeconds}`)).toEqual(expected);
    });

    test('two archive configs are provided', () => {
        const expected = new Map<string, number>();
        const resourceType1 = 'AuditEvent';
        const ttlInSeconds1 = 15780000;
        const resourceType2 = 'Patient';
        const ttlInSeconds2 = 30000000;
        expected.set(resourceType1, ttlInSeconds1);
        expected.set(resourceType2, ttlInSeconds2);

        expect(
            utility.parseArchiveConfig(`${resourceType1} , ${ttlInSeconds1} | ${resourceType2},${ttlInSeconds2}`),
        ).toEqual(expected);
    });

    test('invalid archive config is provided', () => {
        const expected = new Map<string, number>();
        const resourceType = 'AuditEvent';
        const ttlInSeconds = 15780000;
        expected.set(resourceType, ttlInSeconds);
        expect(() => {
            utility.parseArchiveConfig(`${resourceType}:${ttlInSeconds}`);
        }).toThrowError();
    });
});

describe('filter removed records from TTL elapse', () => {
    test('filter out all removed records from TTL elapse', () => {
        const expectedRecords = [
            {
                eventID: '1',
                eventName: 'REMOVE',
                userIdentity: {
                    principalId: 'dynamodb.amazonaws.com',
                    type: 'Service',
                },
            },
            {
                eventID: '2',
                eventName: 'REMOVE',
                userIdentity: {
                    principalId: 'dynamodb.amazonaws.com',
                    type: 'Service',
                },
            },
        ];

        const records = [
            ...expectedRecords,
            {
                eventID: '3',
                eventName: 'INSERT',
                userIdentity: {
                    principalId: 'dynamodb.amazonaws.com',
                    type: 'Service',
                },
            },
            {
                eventID: '4',
                eventName: 'REMOVE',
            },
        ];

        expect(utility.filterRemovedRecordsFromTTL(records)).toEqual(expectedRecords);
    });
});

describe('filter records that needs to update TTL field', () => {
    const DEFAULT_TTL_IN_SECONDS = new Map();
    DEFAULT_TTL_IN_SECONDS.set('Patient', '150000');

    test('insert a new item', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'INSERT',
                dynamodb: {
                    NewImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual(records);
    });

    test('Resource type is not in ttlsInSeconds map', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'INSERT',
                dynamodb: {
                    NewImage: {
                        resourceType: {
                            S: 'Organization',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual([]);
    });

    test('NewImage is LOCKED status', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'INSERT',
                dynamodb: {
                    OldImage: {
                        resourceType: {
                            S: 'Organization',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                    },
                    NewImage: {
                        resourceType: {
                            S: 'Organization',
                        },
                        documentStatus: {
                            S: 'LOCKED',
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual([]);
    });

    test('update an item', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'MODIFY',
                dynamodb: {
                    OldImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'PENDING',
                        },
                    },
                    NewImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual(records);
    });

    test('delete an item', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'MODIFY',
                dynamodb: {
                    OldImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'PENDING',
                        },
                    },
                    NewImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'DELETED',
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual(records);
    });

    test('update an item only TTL field', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'MODIFY',
                dynamodb: {
                    OldImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                        [dynamodb.TTL_FIELD_NAME]: {
                            N: 1000,
                        },
                    },
                    NewImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                        [dynamodb.TTL_FIELD_NAME]: {
                            N: 2000,
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual([]);
    });

    test('update TTL field for an inserted item', () => {
        const records = [
            {
                eventID: '1',
                eventName: 'MODIFY',
                dynamodb: {
                    OldImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                    },
                    NewImage: {
                        resourceType: {
                            S: 'Patient',
                        },
                        documentStatus: {
                            S: 'AVAILABLE',
                        },
                        [dynamodb.TTL_FIELD_NAME]: {
                            N: 2000,
                        },
                    },
                },
            },
        ];

        expect(utility.filterRecordsNeedUpdateTTL(records, DEFAULT_TTL_IN_SECONDS)).toEqual([]);
    });
});
