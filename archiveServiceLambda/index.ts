import utility from './utility';
import firehose from './firehose';
import dynamodb from './dynamodb';

const ttlsInSeconds = utility.parseArchiveConfig(process.env.ARCHIVE_CONFIG);

exports.handler = async (event: any) => {
    if (event && event.Records) {
        console.log(`DynamoDB stream published ${event.Records.length} records to process.`);

        // get records that were removed from TTL elapse
        let records = utility.filterRemovedRecordsFromTTL(event.Records);
        console.log(`DynamoDB stream published ${records.length} records removed by TTL to process.`);
        await firehose.putRecords(records);

        // get records that need to be updated with TTL field
        records = utility.filterRecordsNeedUpdateTTL(event.Records, ttlsInSeconds);
        console.log(`DynamoDB stream published ${records.length} records that need to be updated with TTL field.`);
        await dynamodb.updateRecords(records, ttlsInSeconds);
    } else {
        console.log('No records published by Dynamodb stream.');
    }
};
