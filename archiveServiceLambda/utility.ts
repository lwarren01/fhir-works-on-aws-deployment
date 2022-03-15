import _ from 'lodash';
import dynamodb from './dynamodb';

/**
 * parses string type archive config and returns it in Map format.
 */
function parseArchiveConfig(archiveConfig: string | undefined): Map<string, number> {
    const result = new Map<string, number>();

    archiveConfig?.split('|').forEach((archiveEntry) => {
        if (archiveEntry.trim().length > 0) {
            const resourceToTTL = archiveEntry.split(',');
            if (resourceToTTL.length === 2 && resourceToTTL[0].trim() && resourceToTTL[1].trim()) {
                try {
                    const ttl = parseInt(resourceToTTL[1], 10);
                    if (ttl <= 0) {
                        throw new Error(`TTL time should be greater than 0: ${ttl}`);
                    }
                    result.set(resourceToTTL[0].trim(), ttl);
                } catch (error) {
                    throw new Error(`Invalid TTL time: ${resourceToTTL[1]}`);
                }
            } else {
                throw new Error(`Invalid archive config: ${archiveEntry}`);
            }
        }
    });

    return result;
}

/**
 * returns a new array that only contains records that were removed from TTL elapse
 */
function filterRemovedRecordsFromTTL(records: any[]): any[] {
    return records.filter(
        (record) =>
            record.eventName === 'REMOVE' &&
            record.userIdentity &&
            record.userIdentity.type === 'Service' &&
            record.userIdentity.principalId === 'dynamodb.amazonaws.com',
    );
}
/**
 * return true if two images are the same except ttl field,
 * otherwise return false.
 */
function isEqualExceptTTL(image1: any, image2: any): boolean {
    return _.isEqual(_.omit(image1, [dynamodb.TTL_FIELD_NAME]), _.omit(image2, [dynamodb.TTL_FIELD_NAME]));
}

/**
 * returns a new array that only contains records that need to be updated with TTL field
 */
function filterRecordsNeedUpdateTTL(records: any[], ttlsInSeconds: Map<string, number>): any[] {
    return records.filter((record) => {
        if (ttlsInSeconds.has(record.dynamodb.NewImage?.resourceType.S)) {
            const documentStatus = record.dynamodb.NewImage.documentStatus.S;
            if (record.eventName === 'INSERT' && documentStatus === 'AVAILABLE') {
                // brand new item is inserted
                return true;
            }

            if (record.eventName === 'MODIFY' && ['AVAILABLE', 'DELETED'].includes(documentStatus)) {
                if (isEqualExceptTTL(record.dynamodb.OldImage, record.dynamodb.NewImage)) {
                    // this update is triggered by this lambda function.
                    // return false in oder to avoid infinite loop
                    return false;
                }

                return true;
            }
        }

        return false;
    });
}

export default {
    parseArchiveConfig,
    filterRemovedRecordsFromTTL,
    filterRecordsNeedUpdateTTL,
    isEqualExceptTTL,
};
