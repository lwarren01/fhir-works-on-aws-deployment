import { handleDdbToS3Event } from 'fhir-works-on-aws-persistence-ddb';

exports.handler = async (event: any) => {
    await handleDdbToS3Event(event);
};
