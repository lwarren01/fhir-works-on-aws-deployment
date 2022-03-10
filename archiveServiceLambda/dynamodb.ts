import AWS from 'aws-sdk';
import _ from 'lodash';

const TTL_FIELD_NAME = '_ttlInSeconds';
const DEFAULT_BATCH_SIZE = 10;
const BATCH_SIZE = parseInt(process.env.DYNAMODB_BATCH_SIZE || DEFAULT_BATCH_SIZE.toString(), 10);
const TABLE_NAME = process.env.RESOURCE_TABLE || '';

function getStatement(record: any, ttlsInSeconds: Map<string, number>): string {
    const resourceType = record.dynamodb.NewImage.resourceType.S;
    const ttl = Math.floor(Date.now() / 1000) + ttlsInSeconds.get(resourceType)!;
    const id = record.dynamodb.Keys.id.S;
    const vid = record.dynamodb.Keys.vid.N;
    return `UPDATE "${TABLE_NAME}" SET _ttlInSeconds = ${ttl} WHERE id = '${id}' AND vid = ${vid}`;
}

/**
 * puts records to Firehose delivery stream in chunks
 */
async function updateRecords(records: any[], ttlsInSeconds: Map<string, number>) {
    if (records.length === 0) {
        return;
    }

    const statements = records.map((record) => {
        return { Statement: getStatement(record, ttlsInSeconds) };
    });

    const dynamodb = new AWS.DynamoDB();
    const chunks = _.chunk(statements, BATCH_SIZE);
    const promises = chunks.map((chunk) =>
        dynamodb
            .batchExecuteStatement({
                Statements: chunk,
            })
            .promise(),
    );
    const results: any[] = await Promise.allSettled(promises);
    const errors = results.flatMap((result) => {
        if (result.reason) {
            return [result.reason];
        }
        return result.value.Responses.filter((response: any) => response.Error);
    });

    if (errors.length > 0) {
        console.log(`sing sad songs, ${errors.length} items failed. ${JSON.stringify(errors, null, 2)}`);
    } else {
        console.log(`sing happy songs, ${records.length} items are updated`);
    }
}

export default { TTL_FIELD_NAME, updateRecords };
