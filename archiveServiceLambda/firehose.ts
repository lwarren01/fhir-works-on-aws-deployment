import AWS from 'aws-sdk';
import _ from 'lodash';

const DEFAULT_BATCH_SIZE = 10; // limit of 4 MB for the entire batch.
const BATCH_SIZE = parseInt(process.env.FIREHOSE_BATCH_SIZE || DEFAULT_BATCH_SIZE.toString(), 10);
const DELIVERY_STREAM_NAME = process.env.ARCHIVE_DELIVERY_STREAM_NAME || '';
const NEW_LINE = '\n';

/**
 * puts records to Firehose delivery stream in chunks
 */
async function putRecords(records: any[]) {
    if (records.length === 0) {
        return;
    }
    const firehose = new AWS.Firehose();
    const projectedRecords = records.map((record) => {
        return {
            Data: JSON.stringify(record) + NEW_LINE,
        };
    });
    const chunks = _.chunk(projectedRecords, BATCH_SIZE);

    // TODO: retry logic
    // If the exception persists, it is possible that the throughput limits have been exceeded for the delivery stream.
    const promises = chunks.map((chunk) =>
        firehose
            .putRecordBatch({
                Records: chunk,
                DeliveryStreamName: DELIVERY_STREAM_NAME,
            })
            .promise(),
    );
    const results: any[] = await Promise.allSettled(promises);
    const errors = results.flatMap((result) => {
        if (result.reason) {
            return [result.reason];
        }
        return result.value.RequestResponses.filter((requestResponse: any) => requestResponse.ErrorCode);
    });

    if (errors.length > 0) {
        console.log(`sing sad songs, ${errors.length} records failed. ${JSON.stringify(errors, null, 2)}`);
    } else {
        console.log(`sing happy songs, ${records.length} records pushed to delivery stream`);
    }
}

export default { putRecords };
