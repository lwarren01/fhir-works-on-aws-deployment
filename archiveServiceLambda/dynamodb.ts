import AWS from 'aws-sdk';
import _ from 'lodash';
import type { BatchStatementRequest } from 'aws-sdk/clients/dynamodb';

const TTL_FIELD_NAME = '_ttlInSeconds';
const DEFAULT_BATCH_SIZE = 10;
const BATCH_SIZE = parseInt(process.env.DYNAMODB_BATCH_SIZE || DEFAULT_BATCH_SIZE.toString(), 10);
const TABLE_NAME = process.env.RESOURCE_TABLE || '';

// function getStatement(record: any, ttlsInSeconds: Map<string, number>): string {
//     const resourceType = record.dynamodb.NewImage.resourceType.S;
//     const ttl = Math.floor(Date.now() / 1000) + ttlsInSeconds.get(resourceType)!;
//     const id = record.dynamodb.Keys.id.S;
//     const vid = record.dynamodb.Keys.vid.N;
//     return `UPDATE "${TABLE_NAME}" SET _ttlInSeconds = ${ttl} WHERE id = '${id}' AND vid = ${vid}`;
// }

function getQueryStatement(record: any): string {
    return `SELECT * FROM "${TABLE_NAME}" WHERE "id" = '${record.dynamodb.Keys.id.S}'`;
}

async function runStatements(statements: BatchStatementRequest[]) {
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
        console.log(`${errors.length} statements failed. ${JSON.stringify(errors, null, 2)}`);
    } else {
        console.log(`${statements.length} statements succeeded.`);
    }

    return results;
}

/**
 * puts records to Firehose delivery stream in chunks
 */
async function updateRecords(records: any[], ttlsInSeconds: Map<string, number>) {
    if (records.length === 0) {
        return;
    }

    const statements = _.uniq(records.map((record) => getQueryStatement(record))).map((statement) => {
        return { Statement: statement };
    });

    const results = await runStatements(statements);

    console.log(ttlsInSeconds);
    console.log(results);
}

export default { TTL_FIELD_NAME, updateRecords };
