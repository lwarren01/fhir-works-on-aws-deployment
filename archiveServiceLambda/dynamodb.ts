import AWS from 'aws-sdk';
import _ from 'lodash';
import type { BatchStatementRequest } from 'aws-sdk/clients/dynamodb';

const TTL_FIELD_NAME = '_ttlInSeconds';
const DEFAULT_BATCH_SIZE = 10;
const BATCH_SIZE = parseInt(process.env.DYNAMODB_BATCH_SIZE || DEFAULT_BATCH_SIZE.toString(), 10);
const TABLE_NAME = process.env.RESOURCE_TABLE || 'table';

function getStatements(records: any[], ttlsInSeconds: Map<string, number>): BatchStatementRequest[] {
    const statements = new Set<string>();
    const now = Math.floor(Date.now() / 1000);

    records.forEach((record) => {
        const resourceType = record.dynamodb.NewImage.resourceType.S;
        const ttl = now + ttlsInSeconds.get(resourceType)!;
        const id = record.dynamodb.Keys.id.S;
        const vid = record.dynamodb.Keys.vid.N;

        for (let i = 1; i <= vid; i += 1) {
            statements.add(`UPDATE "${TABLE_NAME}" SET _ttlInSeconds = ${ttl} WHERE "id" = '${id}' AND "vid" = ${i}`);
        }
    });

    return Array.from(statements).map((statement) => {
        return { Statement: statement };
    });
}

async function runStatements(statements: BatchStatementRequest[]): Promise<void> {
    if (statements.length === 0) {
        return;
    }

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
        console.log(`sing sad songs, ${errors.length} statements failed. ${JSON.stringify(errors, null, 2)}`);
    } else {
        console.log(`sing happy songs, ${statements.length} statements succeeded.`);
    }
}

/**
 * puts records to Firehose delivery stream in chunks
 */
async function updateRecords(records: any[], ttlsInSeconds: Map<string, number>) {
    if (records.length === 0) {
        return;
    }

    await runStatements(getStatements(records, ttlsInSeconds));
}

export default { TTL_FIELD_NAME, updateRecords };
